# ELSEWHERE!!
module ICR
  class_getter types = {} of Crystal::Path => Crystal::Type
end

class Crystal::ASTNode
  def run
    raise_error "Not Implemented ASTNode: #{self.class}"
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

class Crystal::StringLiteral
  def run
    ICR.string(self.to_s[1...-1])
  end
end

class Crystal::BoolLiteral
  def run
    ICR.bool(self.to_s == "true")
  end
end

class Crystal::NumberLiteral
  def run
    case kind
    when :i32
      ICR.int32 self.to_s.to_i32
    when :f64
      ICR.float64 self.to_s.to_f64
    else
      raise_error "NumberLiteral kind not implemented #{kind}"
    end
  end
end

class Crystal::TupleLiteral
  def run
    ICR.tuple(self.elements.map &.run)
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
    when Crystal::Var
      ICR.assign_var(t.name, self.value.run)
    when Crystal::InstanceVar
      ICR.assign_ivar(t.name, self.value.run)
    when Crystal::Underscore
      raise_error "Can't assign to '_'"
    else
      raise_error "Unsupported assign target #{t.class}"
    end
  end
end

# Classes & de

class Crystal::Def
  def run
    ICR.nil
  end
end

class Crystal::ClassDef
  def run
    ICR.types[self.name] = self.resolved_type
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
    if type = ICR.types[self]
      ICR.class_type(type)
    else
      raise_error "Path not resolved"
    end
  end
end

class Crystal::Call
  def run
    if obj = self.obj
      receiver = obj.run
      type = receiver.get_type

      if self.name == "new" && receiver.is_a? ICR::ICRClass
        ICR.type_to_allocate = receiver.get_value
      end

      if type.has_def? self.name
        type.lookup_defs(self.name).each do |a_def|
          if a = a_def.annotations(ICR.program.primitive_annotation)
            return ICR::Primitives.call(a[0].args[0].as(Crystal::SymbolLiteral).to_s, a_def, receiver, args.map &.run)
          else
            return ICR.run_method(receiver, a_def, args.map &.run)
          end
        end
      else
        raise_error "Method not found: #{self.name}"
      end
    else
      # top level call
      if ICR.program.has_def? name
        # defs = ICR.program.defs[name]?

        ICR.program.lookup_defs(name).each do |a_def|
          # TODO find good overload
          # raise_error "Top level method not implemented!"
          return ICR.run_top_level_method(a_def, args.map &.run)
        end
      else
        raise_error "Top level method not found: #{name}"
      end
    end
    raise "BUG: not method founds for :#{self.name}"
  rescue e : ICR::Return
    return e.return_value
  end
end

# Primitives #

class Crystal::Primitive
  def run
    ICR::Primitives.call(name)
  end
end

# class Crystal::PointerOf
#   def run
#     ICR.pointer_of(exp.run)
#   end
# end

class Crystal::IsA
  # self.nil_check?
  def run
    o = self.obj.run.get_type
    if (c = const.run).is_a?(ICR::ICRClass)
      ICR.bool !!(o.covariant? c.get_value)
    else
      raise "BUG: IsA const should be a ICRClass"
    end
  end
end

class Crystal::Cast
  def run
    obj.run
  end
end

class Crystal::RespondsTo
  def run
    type = self.obj.run.get_type
    ICR.bool !!(type.has_def? self.name)
  end
end

# Control flow #

class Crystal::Expressions
  def run
    expressions.map(&.run)[-1]
  end
end

class Crystal::Not
  def run
    ICR.bool(!self.exp.run.truthy?)
  end
end

class Crystal::And
  def run
    l = left.run
    l.truthy? ? right.run : l
  end
end

class Crystal::Or
  def run
    l = left.run
    l.truthy? ? l : right.run
  end
end

class Crystal::If
  def run
    if cond.run.truthy?
      self.then.run
    else
      self.else.run
    end
  end
end

class Crystal::While
  def run
    while cond.run.truthy?
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

###
