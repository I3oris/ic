module ICR
  class FunctionCallContext
    getter receiver, args, function_name

    def initialize(@receiver : ICRObject?, @args : Hash(String, ICRObject), @function_name : String)
    end
  end

  @@callstack = [] of FunctionCallContext
  @@top_level_vars = {} of String => ICRObject

  def self.with_context(c : FunctionCallContext, &) : ICRObject
    @@callstack << c
    ret = yield
    @@callstack.pop
    ret
  end

  def self.clear_callstack
    @@callstack.clear
  end

  def self.run_method(receiver, a_def, args) : ICRObject
    if a_def.args.size != args.size
      bug "args doesn't match with def"
    end
    hash = {} of String => ICRObject
    a_def.args.each_with_index { |a, i| hash[a.name] = args[i] }

    receiver ||= @@callstack.last?.try &.receiver # if receiver if nil, take the receiver of the last call

    self.with_context FunctionCallContext.new(receiver, hash, a_def.name) do
      {% if flag?(:_debug) %}
        puts
        context = @@callstack.last
        puts "====== Call #{context.function_name} (#{context.receiver.try &.type.cr_type}) ======"
        puts a_def.body.print_debug
      {% end %}

      ret = a_def.body.run

      {% if flag?(:_debug) %}
        puts
        puts "===== End Call #{context.function_name} ======"
      {% end %}
      ret
    end
  end

  def self.get_var(name) : ICRObject
    if c = @@callstack.last?
      case name
      when "self"
        c.receiver || bug "Cannot found receiver for 'self'"
      else
        c.args[name]? || bug "Cannot found argument '#{name}'"
      end
    else
      @@top_level_vars[name]? || bug "Cannot found top level var '#{name}'"
    end
  end

  def self.assign_var(name, value : ICRObject) : ICRObject
    if c = @@callstack.last?
      c.args[name] = value
    else
      @@top_level_vars[name] = value
    end
  end

  def self.get_ivar(name) : ICRObject
    if c = @@callstack.last?
      c.receiver.try &.[name] || bug "Cannot found receiver for var '#{name}'"
    else
      bug "Trying to access an ivar without context"
    end
  end

  def self.assign_ivar(name, value : ICRObject) : ICRObject
    if c = @@callstack.last?
      c.receiver.try(&.[name] = value) || bug "Cannot found receiver for ivar '#{name}'"
    else
      bug "Trying to assign an ivar without context"
    end
  end

  def self.current_function_name
    @@callstack.last?.try &.function_name || bug "Trying to get the current function name, without having call a function"
  end

  def self.get_symbol_value(name : String)
    ICR.program.symbols.index(name) || bug "Cannot found the symbol :#{name}"
  end

  def self.get_symbol_from_value(value : Int32)
    ICR.program.symbols.each_with_index do |s, i|
      return s if i == value
    end
    bug "Cannot found the symbol corresponding to the value #{value}"
  end
end
