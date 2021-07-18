module IC
  @@consts = {} of String => ICObject
  @@global = {} of String => ICObject
  @@cvars = Hash(Type, Hash(String, ICObject)).new do |hash, key|
    hash[key] = {} of String => ICObject
  end

  module VarStack
    record Vars,
      vars = {} of String => ICObject,
      yield_vars = false

    @@vars = [Vars.new]

    def self.push(vars, yield_vars = false, &)
      @@vars << Vars.new(vars, yield_vars)
      yield
    ensure
      @@vars.pop
    end

    def self.pop(all_yield_vars = false, &)
      reserve = [] of Vars
      if all_yield_vars
        while @@vars.last?.try &.yield_vars
          reserve << @@vars.pop
        end
      end

      c = @@vars.pop? || bug! "VarStack shouldn't be empty"
      begin
        yield c
      ensure
        @@vars << c
        while v = reserve.pop?
          @@vars << v
        end
      end
    end

    def self.[](name) : ICObject
      @@vars.reverse_each do |v|
        return v.vars[name]? || next
      end
      bug! "Cannot found the var '#{name}'"
    end

    def self.assign(type, name, value : ICObject) : ICObject
      @@vars.reverse_each do |v|
        if var = v.vars[name]?
          # update the existing var, and merge his type with the assigned type:
          merged_type = IC.program.type_merge([var.type, type]) || bug! "Cannot merge type of #{name}: #{var.type} + #{type}"
          v.vars[name] = var.updated(merged_type)
          return v.vars[name].assign value
        else
          next if v.yield_vars

          # Allocate slot for a new var:
          return v.vars[name] = ICObject.create_var(type, value)
        end
      end
      bug! "Cannot set the var '#{name}', VarStack contain only yield vars"
    end

    def self.reset
      @@vars = [Vars.new]
    end

    def self.top_level_vars
      @@vars.first.vars
    end
  end

  def self.self_var : ICObject
    CallStack.last_receiver
  end

  def self.get_var(name) : ICObject
    case name
    when "self"
      self_var
    when .starts_with? '$'
      get_global(name)
    else
      VarStack[name]
    end
  end

  def self.assign_var(type, name, value : ICObject) : ICObject
    case name
    when .starts_with? '$'
      assign_global(name, value)
    else
      VarStack.assign(type, name, value)
    end
  end

  def self.get_ivar(name) : ICObject
    CallStack.last_receiver[name]
  end

  def self.assign_ivar(name, value : ICObject) : ICObject
    CallStack.last_receiver[name] = value
  end

  def self.get_cvar(name, var) : ICObject
    @@cvars[var.owner][name]? || begin
      # If cvar not found, initializer must be executed
      # If no initializer, return nil (i.e. `@@foo : Int32?` is nil)
      @@cvars[var.owner][name] = var.initializer.try &.node.run || IC.nil
    end
  end

  def self.assign_cvar(name, value : ICObject, owner : Type) : ICObject
    @@cvars[owner][name] = value
  end

  def self.get_const_value(const) : ICObject
    @@consts[const.full_name]? || begin
      @@consts[const.full_name] = const.value.run
    end
  end

  def self.get_global(name) : ICObject
    @@global[name]? || IC.nil
  end

  def self.assign_global(name, value : ICObject) : ICObject
    @@global[name] = value
  end

  def self.underscore=(value : ICObject)
    value = value.unboxed
    meta_var = Crystal::MetaVar.new "__", value.type

    @@program.@vars["__"] = meta_var
    IC.main_visitor.@vars["__"] = meta_var
    VarStack.top_level_vars["__"] = value
  end

  def self.declared_vars_syntax
    vars = [Set{"__"}]
    # use @@program.vars ?
    VarStack.top_level_vars.each do |name, _|
      vars.last.add(name)
    end
    vars
  end

  def self.declared_vars
    vars_names = VarStack.top_level_vars.keys
    @@program.vars.select &.in? vars_names
  end

  def self.update_vars
    VarStack.top_level_vars.each do |name, obj|
      var = @@program.vars[name]? || next
      VarStack.top_level_vars[name] = obj.updated(var.type)
    end
  end
end
