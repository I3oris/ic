module ICR
  class Primitives
    def self.call(p : Crystal::Primitive)
      {% if flag?(:_debug) %}
        puts "Primitve called: #{p.name}:#{p.type}:#{p.extra}"
      {% end %}

      case p.name
      when "allocate" then self.allocate(p.type)
      else
        todo "Primitive #{name}"
      end
    end

    def self.call(name : String, a_def, type : Crystal::Type, arg0 : ICRObject, args : Array(ICRObject))
      {% if flag?(:_debug) %}
        puts "Primitve called with args: #{name}:"
      {% end %}

      case name
      when ":binary"    then self.binary_call(a_def, arg0, args[0])
      # when ":class"     then ICR.class_type(arg0.type)
      # when ":object_id" then ICR.uint64(arg0.object_id)
      when ":pointer_malloc" then
        type = ICRType.new(type).generics["T"]
        self.pointer_malloc_of(type,args[0])
      when ":pointer_get" then self.pointer_get(arg0)
      when ":pointer_set" then self.pointer_set(arg0,args[0])
      when ":pointer_add" then self.pointer_add(arg0,args[0])
      else
        todo "Primitive #{name}"
      end
    end

    # private def self.get_meta_type(type : Crystal::Type)
    #   case type.to_s
    #   when "Int32" then Int32
    #   when "UInt64" then UInt64
    #   when "Bool" then Bool
    #   else
    #     raise_error "BUG: unsuported type in binary primitive"
    #   end
    # end

    private def self.binary_call(a_def,arg0 : ICRObject, arg1 : ICRObject)
      if arg0.type.@cr_type.to_s != "Int32"
        todo "Binary primitives other that Int32"
      end

      case a_def.name
      when "+" then ICR.int32(arg0.as_int32 + arg1.as_int32)
      when "-" then ICR.int32(arg0.as_int32 - arg1.as_int32)
      when "*" then ICR.int32(arg0.as_int32 * arg1.as_int32)
      when "<" then ICR.bool(arg0.as_int32 < arg1.as_int32)
      when ">" then ICR.bool(arg0.as_int32 > arg1.as_int32)
      when "!=" then ICR.bool(arg0.as_int32 != arg1.as_int32)
      when "==" then ICR.bool(arg0.as_int32 == arg1.as_int32)
      when "<=" then ICR.bool(arg0.as_int32 <= arg1.as_int32)
      when ">=" then ICR.bool(arg0.as_int32 >= arg1.as_int32)
      else
        todo "Primitive #{a_def.name}"
      end
    end
    # private def self.binary_call(a_def, arg0 : ICRObject, arg1 : ICRObject)
    #   t1 = self.get_meta_type(a_def.owner)
    #   t2 = self.get_meta_type(a_def.args[0].type)
    #   # ret = self.get_meta_type(a_def.return_type.)
    #   ret = t1

    #   obj = ICRObject.new(ICRType.new(a_def.owner))
    #   {% begin %}
    #   result = case op_name = a_def.name
    #     {% for op in %w(+ * -) %}
    #       when {{op}} then arg0.as_number(t1) {{op.id}} arg1.as_number(t2)
    #     {% end %}

    #     {% for op in %w(== != <= >= < >) %}
    #       # when {{op}} then ICRBool.new(@value {{op.id}} other.value)
    #     {% end %}
    #   else
    #     raise_error "BUG: unsuported primitive #{op_name}"
    #   end
    #   {% end %}

    #   obj.set_as_number(ret,result)
    #   obj
    #   # arg0.unsafe_as(ICRNumber).primitive_op(a_def.name,arg1.as(ICRNumber))
    #   # t1, t2 = a_def.owner , a_def.args[0].type
    #   # case a_def.name
    #   # when
    #   # when "+"  then T.new(arg0.value + arg1.value)
    #   # when "*"  then T.new(arg0.value * arg1.value)
    #   # when "-"  then T.new(arg0.value - arg1.value)
    #   # when "==" then ICR.bool(arg0.value == arg1.value)
    #   # when "!=" then ICR.bool(arg0.value != arg1.value)
    #   # when "<=" then ICR.bool(arg0.value <= arg1.value)
    #   # when ">=" then ICR.bool(arg0.value >= arg1.value)
    #   # when "<"  then ICR.bool(arg0.value < arg1.value)
    #   # when ">"  then ICR.bool(arg0.value > arg1.value)
    #   # else
    #   #   raise_error "Binary primitive not implemented: #{name}" # where is definied name??
    #   # end
    # end

    private def self.allocate(type)
      ICRObject.new(ICRType.new(type.not_nil!)) rescue bug "No type to allocate"
    end

    private def self.pointer_malloc_of(generic : ICRType, size : ICRObject)# Generic ICRType?
      size = size.as_uint64 * generic.size
      p = ICRObject.new(ICRType.pointer_of(generic.@cr_type))
      p.as_uint64 = Pointer(UInt8).malloc(size).address
      p
    end

    private def self.pointer_set(p : ICRObject, value : ICRObject)
      src = value.raw
      dst = Pointer(UInt8).new(p.as_uint64)
      src.copy_to(dst, p.type.generics["T"].size)
      value
    end

    private def self.pointer_get(p : ICRObject)
      type = p.type.generics["T"]
      obj = ICRObject.new(type)
      scr = Pointer(UInt8).new(p.as_uint64)
      dst = obj.raw
      scr.copy_to(dst, type.size)
      obj
    end

    private def self.pointer_add(p : ICRObject, x : ICRObject)
      new_p = ICRObject.new(p.type)
      new_p.as_uint64 = p.as_uint64 + x.as_int32*p.type.generics["T"].size
      new_p
    end
  end
end
