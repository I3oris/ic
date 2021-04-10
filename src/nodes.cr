class Crystal::ASTNode
  def run
    todo "ASTNode: #{self.class}"
  end

  def print_debug(visited = [] of Crystal::ASTNode, indent = 0)
    if self.in? visited
      print "..."
      return
    end
    visited << self

    print {{@type}}
    puts ':'
    {% for ivar in @type.instance_vars.reject { |iv| %w(location end_location name_location doc observers parent_visitor).includes? iv.stringify } %}
      print "  "*(indent+1)
      print "@{{ivar}} = "
      if (ivar = @{{ivar}}).is_a? Crystal::ASTNode
        ivar.print_debug(visited,indent+1)
      else
        print @{{ivar}}.inspect
      end
      puts
    {% end %}
  end
end

class Crystal::Nop
  def run
    ICR.nil
  end
end

# Literals #

class Crystal::NilLiteral
  def run
    ICR.nil
  end
end

class Crystal::CharLiteral
  def run
    ICR.char(self.value)
  end
end

class Crystal::StringLiteral
  def run
    ICR.string(self.value)
  end
end

class Crystal::BoolLiteral
  def run
    ICR.bool(self.value)
  end
end

class Crystal::NumberLiteral
  def run
    case self.kind
    when :f32  then ICR.number self.value.to_f32
    when :f64  then ICR.number self.value.to_f64
    when :i128 then todo "Big Integer"
    when :u128 then todo "Big Integer"
    else            ICR.number self.integer_value
    end
  end
end

class Crystal::SymbolLiteral
  def run
    ICR.symbol(self.value)
  end
end

class Crystal::TupleLiteral
  def run
    ICR.tuple(self.type, self.elements.map &.run)
  end
end

class Crystal::NamedTupleLiteral
  def run
    ICR.tuple(self.type, self.entries.map &.value.run)
  end
end

# Vars #

class Crystal::Underscore
  def run
    ICR.result
  end
end

class Crystal::Var
  def run
    ICR.get_var(self.name)
  end
end

class Crystal::InstanceVar
  def run
    ICR.get_ivar(self.name)
  end
end

class Crystal::Assign
  def run
    case t = self.target
    when Crystal::Var         then ICR.assign_var(t.name, self.value.run)
    when Crystal::InstanceVar then ICR.assign_ivar(t.name, self.value.run)
    when Crystal::ClassVar    then todo "ClassVar assign"
    when Crystal::Underscore  then icr_error "Can't assign to '_'"
    when Crystal::Path        then todo "CONST assign"
    else                           bug "Unexpected assign target #{t.class}"
    end
  end
end

class Crystal::UninitializedVar
  def run
    case v = self.var
    when Crystal::Var         then ICR.assign_var(v.name, ICR.uninitialized(self.type))
    when Crystal::InstanceVar then ICR.assign_ivar(v.name, ICR.uninitialized(self.type))
    when Crystal::ClassVar    then todo "Uninitialized cvar"
    when Crystal::Underscore  then todo "Uninitialized underscore"
    when Crystal::Path        then todo "Uninitialized CONST"
    else                           bug "Unexpected uninitialized-assign target #{v.class}"
    end
  end
end

# Classes & Defs

class Crystal::Def
  def run
    ICR.nil
  end
end

class Crystal::ClassDef
  def run
    ICR.nil
  end
end

class Crystal::ModuleDef
  def run
    ICR.nil
  end
end

class Crystal::Macro
  def run
    ICR.nil
  end
end

class Crystal::Annotation
  def run
    ICR.nil
  end
end

# Calls #

class Crystal::Path
  def run
    ICR.class(self.type)
  end
end

class Crystal::Generic
  def run
    ICR.class(self.type)
  end
end

class Crystal::Call
  def run
    if a_def = self.target_defs.try &.first? # TODO, lockup self.type, and depending of the receiver.type, take the good target_def

      return ICR.run_method(self.obj.try &.run, a_def, self.args.map &.run)
    else
      bug "Cannot find target def matching with this call: #{name}"
    end
  rescue e : ICR::Return
    return e.return_value
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
    ICR.bool(!self.exp.run.truthy?)
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
      rescue ICR::Break
        break
      rescue ICR::Next
        next
      end
    end
    ICR.nil
  end
end

class ICR::Break < Exception
end

class ICR::Next < Exception
end

class ICR::Return < Exception
  getter return_value

  def initialize(@return_value : ICR::ICRObject)
  end
end

class Crystal::Next
  def run
    ::raise ICR::Next.new
  end
end

class Crystal::Break
  def run
    ::raise ICR::Break.new
  end
end

class Crystal::Return
  def run
    if exp = self.exp
      ::raise ICR::Return.new exp.run
    else
      ::raise ICR::Return.new ICR.nil
    end
  end
end

# Primitives #

class Crystal::Primitive
  def run
    ICR::Primitives.call(self)
  end
end

class Crystal::PointerOf
  def run
    if (exp = self.exp).is_a?(InstanceVar)
      # when `pointerof(@foo)` is written, pointerof return a
      # pointer on `self` +  offsetof @foo
      ICR.get_var("self").pointerof(ivar: exp.name)
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
      ICR.nil
    end
  end
end

class Crystal::IsA
  def run
    ICR.bool self.obj.run.is_a self.const.type
  end
end

class Crystal::RespondsTo
  def run
    type = self.obj.run.type.cr_type
    ICR.bool !!(type.has_def? self.name)
  end
end

class Crystal::TypeOf
  def run
    ICR.class(self.type)
  end
end

# Others #

class Crystal::FileNode
  def run
    self.node.run
  end
end
