module ICR
  class_property type_to_allocate : Crystal::Type? = nil

  class Primitives
    def self.call(name : String)
      case name
      when "allocate" then self.allocate(ICR.type_to_allocate)
      else
        raise_error "Primitive not implemented: #{name}"
      end
    end

    def self.call(name : String, a_def, arg0 : ICRObject, args : Array(ICRObject))
      case name
      when ":binary"    then self.binary_call(a_def, arg0, args[0])
      when ":class"     then ICR.class_type(arg0.type)
      when ":object_id" then ICR.uint64(arg0.object_id)
      else
        raise_error "Primitive not implemented: #{name}"
      end
    end

    private def self.binary_call(a_def, arg0 : ICRObject, arg1 : ICRObject)
      arg0.unsafe_as(ICRNumber).primitive_op(a_def.name,arg1.as(ICRNumber))
      # t1, t2 = a_def.owner , a_def.args[0].type
      # case a_def.name
      # when
      # when "+"  then T.new(arg0.value + arg1.value)
      # when "*"  then T.new(arg0.value * arg1.value)
      # when "-"  then T.new(arg0.value - arg1.value)
      # when "==" then ICR.bool(arg0.value == arg1.value)
      # when "!=" then ICR.bool(arg0.value != arg1.value)
      # when "<=" then ICR.bool(arg0.value <= arg1.value)
      # when ">=" then ICR.bool(arg0.value >= arg1.value)
      # when "<"  then ICR.bool(arg0.value < arg1.value)
      # when ">"  then ICR.bool(arg0.value > arg1.value)
      # else
      #   raise_error "Binary primitive not implemented: #{name}" # where is definied name??
      # end
    end

    private def self.allocate(type)
      if type
        ICR.type_to_allocate = nil
        if type.struct?
          ICRStruct.new(type)
        else
          ICRReference.new(type)
        end
      else
        raise "BUG: Trying to allocate nothing"
      end
      # case type.to_s
      # when "Nil"     then ICR.nil
      # when "Bool"    then ICR.bool(false)
      # when "Int32"   then Box(Int32).unbox(@value)
      # when "Float64" then Box(Float64).unbox(@value)
      # when "String"  then Box(String).unbox(@value)
      # else                raise_error "Not Implemented type for 'get_value': #{@type}"
      # end
    end
  end
end
