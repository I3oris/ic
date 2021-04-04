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

    self.with_context FunctionCallContext.new(receiver, hash, a_def.name) do
      a_def.body.run
    end
  end

  # def self.run_top_level_method(a_def, args) : ICRObject
  #   self.run_method(nil, a_def, args)
  # end

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
end
