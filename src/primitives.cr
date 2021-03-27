module ICR
  class Primitives
    def self.call(name : String, a_def, arg0 : ICRObject, args : Array(ICRObject))
      case name
      when ":binary" then self.binary_call(a_def, arg0, args[0])
      else
        raise_error "Primitive not implemented: #{name}"
      end
    end

    private def self.binary_call(a_def, arg0, arg1)
      # t1, t2 = a_def.owner , a_def.args[0].type
      case a_def.name
      when "+"  then ICR.int32(arg0.get_value.as(Int32) + arg1.get_value.as(Int32))
      when "*"  then ICR.int32(arg0.get_value.as(Int32) * arg1.get_value.as(Int32))
      when "-"  then ICR.int32(arg0.get_value.as(Int32) - arg1.get_value.as(Int32))
      when "==" then ICR.bool(arg0.get_value.as(Int32) == arg1.get_value.as(Int32))
      when "!=" then ICR.bool(arg0.get_value.as(Int32) != arg1.get_value.as(Int32))
      when "<=" then ICR.bool(arg0.get_value.as(Int32) <= arg1.get_value.as(Int32))
      when ">=" then ICR.bool(arg0.get_value.as(Int32) >= arg1.get_value.as(Int32))
      when "<"  then ICR.bool(arg0.get_value.as(Int32) < arg1.get_value.as(Int32))
      when ">"  then ICR.bool(arg0.get_value.as(Int32) > arg1.get_value.as(Int32))
      else
        raise_error "Binary primitive not implemented: #{name}"
      end
    end
  end
end
