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

# class Crystal::TupleLiteral

# end

class Crystal::Var
  def run
    ICR.get_var(self.to_s)
  end
end

class Crystal::Assign
  def run
    ICR.assign_var(self.target.to_s, self.value.run)
  end
end

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

class Crystal::Macro
  def run
    ICR.nil
  end
end

class Crystal::Call
  def run
    {% unless flag?(:no_semantic) %}
      if obj = self.obj
        receiver = obj.run
        type = receiver.get_type

        if type.has_def? name
          type.lookup_defs(name).each do |a_def|
            if a = a_def.annotations(ICR.program.primitive_annotation)
              return ICR::Primitives.call(a[0].args[0].as(Crystal::SymbolLiteral).to_s, a_def, receiver, args.map &.run)
            else
              return ICR.run_method(receiver, a_def, args.map &.run)
              # raise_error "Method call not implemented!!"
            end
          end
        else
          raise_error "Method not found #{name}"
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
          raise_error "top level method not found #{name}"
        end
      end
    {% end %}
    ICR.nil
  rescue e : ICR::Return
    return e.return_value
  end
end

class Crystal::Expressions
  def run
    expressions.map(&.run)[-1]
  end
end

class Crystal::If
  def run
    if cond.run.get_value
      self.then.run
    else
      self.else.run
    end
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
    ::raise ICR::Return.new ICR.nil
    # case returns.size
    # when 0 then ::raise ICR::Return.new ICR.nil
    # when 1 then ::raise ICR::Return.new returns[0].run
    # else ::raise ICR::Return.new ICR.tuple(returns.map &.run)
    # end
  end
end

# ReturnGatherer
class Crystal::While
  def run
    while cond.run.get_value
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
