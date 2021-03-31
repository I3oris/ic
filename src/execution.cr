module ICR
  class FunctionCallContext
    getter receiver, args

    def initialize(@receiver : ICRObject?, @args : Hash(String, ICRObject))
    end
  end

  @@contexts = [] of FunctionCallContext
  @@top_level_vars = {} of String => ICRObject

  def self.with_context(c : FunctionCallContext, &) : ICRObject
    @@contexts << c
    ret = yield
    @@contexts.pop
    ret
  end

  # useful when error append into a function
  def self.clear_context
    @@contexts.clear
  end

  def self.run_method(receiver, a_def, args) : ICRObject
    if a_def.args.size != args.size
      raise_error "TODO: default values & named arguments"
    end
    hash = {} of String => ICRObject
    a_def.args.each_with_index { |a, i| hash[a.name] = args[i] }

    self.with_context FunctionCallContext.new(receiver, hash) do
      a_def.body.run
    end
  end

  def self.run_top_level_method(a_def, args) : ICRObject
    self.run_method(nil, a_def, args)
  end

  def self.get_var(name) : ICRObject
    if c = @@contexts.last?
      case name
      when "self"
        c.receiver || raise_error "BUG: Cannot found receiver for self"
      else
        c.args[name]? || raise_error "BUG: Cannot found argument '#{name}'"
      end
    else
      @@top_level_vars[name]? || raise_error "BUG: Cannot found top level var '#{name}'"
    end
  end

  def self.assign_var(name, value : ICRObject) : ICRObject
    if c = @@contexts.last?
      c.args[name] = value
    else
      @@top_level_vars[name] = value
    end
  end

  def self.get_ivar(name) : ICRObject
    if c = @@contexts.last?
      c.receiver.try &.get_ivar(name) || raise_error "BUG: Cannot found receiver for var '#{name}'"
    else
      raise_error "BUG: trying to access a ivar without context"
    end
  end

  def self.assign_ivar(name, value : ICRObject) : ICRObject
    if c = @@contexts.last?
      c.receiver.try &.set_ivar(name, value) || raise_error "BUG: Cannot found receiver for ivar '#{name}'"
    else
      raise_error "BUG: trying to assign a ivar without context"
    end
  end
end
