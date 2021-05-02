class Crystal::ASTNode
  def run
    todo "ASTNode: #{self.class}"
  end
end

class Crystal::Nop
  def run
    IC.nil
  end
end

# Literals #

class Crystal::NilLiteral
  def run
    IC.nil
  end
end

class Crystal::CharLiteral
  def run
    IC.char(self.value)
  end
end

class Crystal::StringLiteral
  def run
    IC.string(self.value)
  end
end

class Crystal::BoolLiteral
  def run
    IC.bool(self.value)
  end
end

class Crystal::NumberLiteral
  def run
    case self.kind
    when :f32  then IC.number self.value.to_f32
    when :f64  then IC.number self.value.to_f64
    when :i128 then todo "Big Integer"
    when :u128 then todo "Big Integer"
    else            IC.number self.integer_value
    end
  end
end

class Crystal::SymbolLiteral
  def run
    IC.symbol(self.value)
  end
end

class Crystal::TupleLiteral
  def run
    IC.tuple(self.type, self.elements.map &.run)
  end
end

class Crystal::NamedTupleLiteral
  def run
    IC.tuple(self.type, self.entries.map &.value.run)
  end
end

# Vars #

# class Crystal::Underscore
#   def run
#     IC.result
#   end
# end

class Crystal::Var
  def run
    IC.get_var(self.name)
  end
end

class Crystal::InstanceVar
  def run
    IC.get_ivar(self.name)
  end
end

class Crystal::Assign
  def run
    case t = self.target
    when Crystal::Var         then IC.assign_var(t.name, self.value.run)
    when Crystal::InstanceVar then IC.assign_ivar(t.name, self.value.run)
    when Crystal::ClassVar    then todo "ClassVar assign"
    when Crystal::Underscore  then ic_error "Can't assign to '_'"
    when Crystal::Path        then IC.assign_const(t.target_const.not_nil!.name, self.value.run)
    else                           bug! "Unexpected assign target #{t.class}"
    end
  end
end

class Crystal::UninitializedVar
  def run
    case v = self.var
    when Crystal::Var         then IC.assign_var(v.name, IC.uninitialized(self.type))
    when Crystal::InstanceVar then IC.assign_ivar(v.name, IC.uninitialized(self.type))
    when Crystal::ClassVar    then todo "Uninitialized cvar"
    when Crystal::Path        then todo "Uninitialized CONST"
    else                           bug! "Unexpected uninitialized-assign target #{v.class}"
    end
  end
end

# Classes & Defs

class Crystal::Def
  def run
    IC.nop
  end
end

class Crystal::ClassDef
  def run
    self.body.run
    IC.nop
  end
end

class Crystal::ModuleDef
  def run
    self.body.run
    IC.nop
  end
end

class Crystal::Macro
  def run
    IC.nop
  end
end

class Crystal::Annotation
  def run
    IC.nop
  end
end

class Crystal::Alias
  def run
    IC.nop
  end
end

class Crystal::VisibilityModifier
  def run
    self.exp.run
  end
end

class Crystal::TypeDeclaration
  def run
    value = self.value.try &.run || IC.nil
    case v = self.var
    when Var then IC.assign_var(v.name, value)
    when InstanceVar # nothing
 then
    when ClassVar # nothing
 then
    else bug! "Unexpected var #{v.class} in type declaration"
    end
    IC.nil
  end
end

# Calls #

class Crystal::Path
  def run
    if const = self.target_const
      IC.get_const(const.name)
    else
      IC.class(self.type)
    end
  end
end

class Crystal::Generic
  def run
    IC.class(self.type)
  end
end

class Crystal::Call
  def run
    if a_def = self.target_defs.try &.first? # TODO, lockup self.type, and depending of the receiver.type, take the good target_def

      return IC.run_method(self.obj.try &.run, a_def, self.args.map &.run, self.block, id: self.object_id)
    else
      bug! "Cannot find target def matching with this call: #{name}"
    end
  rescue e : IC::Return
    IC.handle_return(e)
  rescue e : IC::Break
    IC.handle_break(e, self.object_id)
  end
end

class Crystal::Yield
  def run
    IC.yield(self.exps.map &.run)
  rescue e : IC::Next
    IC.handle_next(e, self.object_id)
  end
end

# Control flow #

class Crystal::Expressions
  def run
    self.expressions.map(&.run)[-1]
  end
end

class Crystal::Not
  def run
    IC.bool(!self.exp.run.truthy?)
  end
end

class Crystal::And
  def run
    l = self.left.run
    l.truthy? ? self.right.run : l
  end
end

class Crystal::Or
  def run
    l = self.left.run
    l.truthy? ? l : self.right.run
  end
end

class Crystal::If
  def run
    if self.cond.run.truthy?
      self.then.run
    else
      self.else.run
    end
  end
end

class Crystal::While
  def run
    while self.cond.run.truthy?
      begin
        self.body.run
      rescue e : IC::Next
        IC.handle_next(e, self.object_id)
        next
      rescue e : IC::Break
        IC.handle_break(e, self.object_id)
        break
      end
    end
    IC.nil
  end
end

class IC::ControlFlowBreak < Exception
  getter value : ICObject
  getter call_id : UInt64

  # value = nil for `return`
  # value = x for `return x`
  # value = {x,y,z,..} for `return x,y,z,...`
  def initialize(args, @call_id)
    @value = args ? args.run : IC.nil
  end
end

class IC::Return < IC::ControlFlowBreak
end

class IC::Next < IC::ControlFlowBreak
end

class IC::Break < IC::ControlFlowBreak
end

class Crystal::Next
  def run
    ::raise IC::Next.new self.exp, self.target.object_id
  end
end

class Crystal::Break
  def run
    ::raise IC::Break.new self.exp, self.target.object_id
  end
end

class Crystal::Return
  def run
    ::raise IC::Return.new self.exp, self.target.object_id
  end
end

# Primitives #

class Crystal::Primitive
  def run
    IC::Primitives.call(self)
  end
end

class Crystal::PointerOf
  def run
    if (exp = self.exp).is_a?(InstanceVar)
      # when it is a pointerof an ivar, take the address of `self` + offsetof @ivar
      IC.get_var("self").pointerof(ivar: exp.name)
    else
      self.exp.run.pointerof_self
    end
  end
end

# Casts #

class Crystal::Cast
  def run
    if new_obj = self.obj.run.cast from: self.obj.type, to: @type
      new_obj
    else
      todo "Raise an error on invalid cast"
    end
  end
end

class Crystal::NilableCast
  def run
    if new_obj = self.obj.run.cast from: self.obj.type, to: @type
      new_obj
    else
      IC.nil
    end
  end
end

class Crystal::IsA
  def run
    IC.bool self.obj.run.is_a self.const.type
  end
end

class Crystal::RespondsTo
  def run
    type = self.obj.run.type.cr_type
    IC.bool !!(type.has_def? self.name)
  end
end

class Crystal::TypeOf
  def run
    IC.class(self.type)
  end
end

# C-binding #

class Crystal::FunDef
  def run
    IC.nop
  end
end

class Crystal::LibDef
  def run
    IC.nop
  end
end

# Others #

class Crystal::FileNode
  def run
    self.node.run
    IC.nop
  end
end
