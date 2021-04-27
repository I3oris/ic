module IC
  # Context when a function is call, contain the slots for instance of function vars (args)
  class FunctionCallContext
    getter receiver, args, function_name

    def initialize(@receiver : ICObject?, @args : Hash(String, ICObject), @function_name : String)
    end
  end

  @@callstack = [] of FunctionCallContext
  @@top_level_vars = {} of String => ICObject
  @@consts = {} of String => ICObject

  def self.with_context(*args, &) : ICObject
    @@callstack << FunctionCallContext.new(*args)
    ret = yield
    @@callstack.pop
    ret
  end

  def self.clear_callstack
    @@callstack.clear
  end

  def self.run_method(receiver, a_def, args) : ICObject
    if a_def.args.size != args.size
      bug! "args doesn't matches with this def"
    end
    hash = {} of String => ICObject
    a_def.args.each_with_index { |a, i| hash[a.name] = args[i] }

    receiver ||= @@callstack.last?.try &.receiver # if receiver if nil, take the receiver of the last call

    self.with_context(receiver, hash, a_def.name) { run_method_body(a_def) }
  end

  private def self.run_method_body(a_def)
    a_def.body.run
  end

  def self.get_var(name) : ICObject
    if c = @@callstack.last?
      case name
      when "self"
        c.receiver || bug! "Cannot found receiver for 'self'"
      else
        c.args[name]? || bug! "Cannot found argument '#{name}'"
      end
    else
      @@top_level_vars[name]? || bug! "Cannot found top level var '#{name}'"
    end
  end

  def self.assign_var(name, value : ICObject, uninitialized? = false) : ICObject
    if c = @@callstack.last?
      c.args[name] = value
    else
      return value if uninitialized? && @@top_level_vars[name]?
      @@top_level_vars[name] = value
    end
  end

  def self.get_ivar(name) : ICObject
    if c = @@callstack.last?
      c.receiver.try &.[name] || bug! "Cannot found receiver for var '#{name}'"
    else
      bug! "Trying to access an ivar without context"
    end
  end

  def self.assign_ivar(name, value : ICObject) : ICObject
    if c = @@callstack.last?
      c.receiver.try(&.[name] = value) || bug! "Cannot found receiver for ivar '#{name}'"
    else
      bug! "Trying to assign an ivar without context"
    end
  end

  def self.get_const(name)
    @@consts[name]? || bug! "Cannot found the CONST '#{name}'"
  end

  def self.assign_const(name, value : ICObject) : ICObject
    @@consts[name] = value
  end

  def self.underscore=(value : ICObject)
    @@top_level_vars["__"] = value
    @@program.@vars["__"] = Crystal::MetaVar.new "__", value.type.cr_type
  end

  def self.clear_vars
    @@program.@vars.clear
    @@top_level_vars.clear
  end

  def self.clear_const
    @@consts.clear
  end

  def self.declared_vars_syntax
    vars = [Set{"__"}]
    # use @@program.vars ?
    @@top_level_vars.each do |name, _|
      vars.last.add(name)
    end
    vars
  end

  def self.declared_vars
    vars_names = @@top_level_vars.keys
    @@program.vars.select &.in? vars_names
  end

  def self.reset
    IC.clear_vars
    IC.clear_callstack
    IC.clear_const
    @@program = Crystal::Program.new
    # @@main_visitor = Crystal::MainVisitor.new(@@program)
    IC.run_file "./ic_prelude.cr"
    @@result = IC.nop
    @@busy = false
    IC.underscore = IC.nil
  end

  def self.current_function_name
    @@callstack.last?.try &.function_name || bug! "Trying to get the current function name, without having call a function"
  end

  def self.symbol_value(name : String)
    IC.program.symbols.index(name) || begin
      # If name not found in the Program, add it.
      #
      # This append on a CONST initialization (i.e. FOO = :foo)
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
  @@crystal_types = Set(Crystal::Type).new

  def self.type_id(type : Crystal::Type, instance = true)
    if instance && type.is_a? Crystal::UnionType || type.is_a? Crystal::VirtualType
      bug! "Cannot get crystal_id_type on a union or virtual type"
    end

    if id = @@crystal_types.index(type)
      id
    else
      @@crystal_types << type
      @@crystal_types.index(type).not_nil!
    end
  end

  def self.type_from_id(id : Int32)
    @@crystal_types.each_with_index do |t, i|
      return t if i == id
    end
    bug! "Cannot found the type corresponding to the id #{id}"
  end
end
