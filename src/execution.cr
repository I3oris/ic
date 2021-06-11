module IC
  module CallStack
    record FunctionCallContext,
      receiver : ICObject?,
      name : String,
      block : Crystal::Block?

    @@callstack = [] of FunctionCallContext

    def self.push(receiver, name, block, &)
      @@callstack << FunctionCallContext.new receiver, name, block
      yield
    ensure
      @@callstack.pop
    end

    def self.pop(&)
      c = @@callstack.pop? || bug! "CallStack shouldn't be empty"
      begin
        yield c
      ensure
        @@callstack << c
      end
    end

    def self.last?
      @@callstack.last?
    end

    def self.last_receiver
      @@callstack.last?.try &.receiver || bug! "Cannot found a receiver on callstack"
    end
  end

  private def self.bind_args(obj, args)
    hash = {} of String => ICObject
    obj.args.each_with_index do |a, i|
      if (enum_t = a.type).is_a? Crystal::EnumType && args[i].type.is_a? Crystal::SymbolType
        hash[a.name] = IC.enum_from_symbol(enum_t, args[i])
      else
        hash[a.name] = args[i].copy # We must copy because function and yield args have their own slot.
      end
    end
    hash
  end

  def self.run_method(receiver, a_def, args, block) : ICObject
    bug! "Args doesn't matches with this def" if a_def.args.size != args.size

    IC.primitives_args = args

    # if receiver if nil, take the receiver of the last call:
    receiver ||= CallStack.last?.try &.receiver

    VarStack.push(bind_args(a_def, args)) do
      CallStack.push(receiver, a_def.name, block) do
        run_method_body(a_def)
      end
    end
  end

  private def self.run_method_body(a_def)
    a_def.body.run
  end

  def self.dispatch_def(receiver, target_defs) : Crystal::Def?
    return nil unless target_defs

    # Don't enable dispatch for now, because it break other spec:
    return target_defs.first?

    if receiver.nil?
      target_defs.first?
    elsif target_defs.size == 1
      target_defs.first
    else
      type = IC.type_from_id(receiver.read_type_id)
      # puts "---many target_defs (#{type}):"
      target_defs.each do |d|
        # pp! d.owner,
        d.original_owner
      end

      defs = target_defs.select do |a_def|
        a_def.original_owner == type || a_def.owner == type
      end

      return nil if defs.size != 1

      defs.first
    end
  end

  def self.yield(args) : ICObject
    CallStack.pop do |c|
      VarStack.pop(all_yield_vars: true) do
        bug! "Cannot found the yield block" unless block = c.block

        # If a tuple is yielded, it must be splatted, unless the block have one argument:
        # i.e:
        # ```
        # def foo
        #   yield({0, 1, 2})
        # end
        #
        # foo { |a, b| puts(a, b) } # => 0 # => 1
        # foo { |a| puts(a) }       # => {0,1,2}
        # ```
        if args.size == 1 && args[0].type.is_a? Crystal::TupleInstanceType
          unless block.args.size == 1
            tuple = args[0]
            args = tuple.type.map_ivars { |name| tuple[name] }
          end
        end

        VarStack.push(bind_args(block, args), yield_vars: true) do
          block.body.run
        end
      end
    end
  end

  def self.handle_break(e, id)
    e.call_id == id ? e.value : (::raise e)
  end

  def self.handle_next(e, id)
    e.value
  end

  def self.handle_return(e)
    e.value
  end

  def self.current_function_name
    CallStack.last?.try &.name || "Cannot found the current function name"
  end

  # Symbol & type id :

  def self.symbol_value(name : String)
    IC.program.symbols.index(name) || begin
      # If name not found in the Program, add it.
      #
      # This happens on a CONST initialization (i.e. FOO = :foo)
      # In this case crystal don't execute the semantics of :foo
      # because it 'see' that FOO is not used.
      IC.program.symbols.add(name).index(name).not_nil!
    end
  end

  def self.symbol_from_value(value : Int32)
    IC.program.symbols.each_with_index do |s, i|
      return s if i == value
    end
    bug! "Cannot found the symbol corresponding to the value #{value}"
  end

  # This Set permit to associate an unique id for each type, works like the `Program::symbol` set.
  @@crystal_types = Set(Type).new

  def self.type_id(type : Type, instance = true)
    if instance && type.is_a? Crystal::UnionType || type.is_a? Crystal::VirtualType
      bug! "Cannot get crystal_id_type on a union or virtual type"
    end

    if id = @@crystal_types.index(type)
      id
    else
      @@crystal_types.add(type).index(type).not_nil!
    end
  end

  def self.type_from_id(id : Int32)
    @@crystal_types.each_with_index do |t, i|
      return t if i == id
    end
    bug! "Cannot found the type corresponding to the id #{id}"
  end

  class_property primitives_args = [] of ICObject
end

module IC
  @@closure_stack = [] of ClosureContext
  record ClosureContext,
    proc_id : UInt64,
    closured_vars = {} of UInt64 => ICObject

  def self.closure_context(proc_id, closured_vars)
    @@closure_stack << ClosureContext.new proc_id, closured_vars
    yield
  ensure
    @@closure_stack.pop
  end

  def self.get_closure_var?(id)
    @@closure_stack.last?.try &.closured_vars[id]?
  end

  # Capture and collect the closured var inside the given proc literal
  # ```
  # x = 1
  # y = 2
  # p = ->(z : Int32) do
  #   x + y + z # (3)
  # end         # (1)
  #
  # p.call 3 # (2)
  # ```
  # At (1): we capture the closured vars `x` & `y` thank to the `ClosuredVarsCollector` and store their current
  # value (get_var("x") & get_var("y")) indexed by their ASTNode object_id
  #
  # At (2): we call the body (3), then the ASTNode `x` & `y` will retrieve theirs value from their object id.
  def self.collect_closured_vars(a_def)
    vars = Crystal::CleanupTransformer::ClosuredVarsCollector.collect a_def

    closured_vars = {} of UInt64 => IC::ICObject
    vars.each do |v|
      case v
      when Crystal::Var
        begin
          closured_vars[v.object_id] = IC.get_var(v.name)
        rescue IC::Error
          # In case of proc argument taken in closure (here `x`):
          # ```
          # get = ->(x : Int32) do
          #   ->{ x }
          # end # (1)
          #
          # get_7 = get.call 7   # (2)
          # get_42 = get.call 42 # (3)
          #
          # get_7.call
          # get_42.call
          # ```
          # at (1), we must ignore the closure var x (because its value is not defined yet)
          # but this only when the body of `get` will be run that we can capture the closure var `x`(at (2) & (3))
          #
          # if ever x is defined but is the wrong x, wrong x will be captured as closure, but
          # the good closure will be captured anyway at (2) & (3).
          #
          # TODO: rescue only missing var errors
        end
      else
        todo "Closure var #{v.class}"
      end
    end
    closured_vars
  end
end
