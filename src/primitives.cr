module ICR
  class Primitives
    def self.call(p : Crystal::Primitive)
      {% if flag?(:_debug) %}
        puts "Primitve called: #{p.name}:#{p.type}:#{p.extra}"
        p.print_debug
      {% end %}

      case p.name
      when "allocate"       then allocate(p.type)
      when "binary"         then binary(ICR.current_function_name, p.type, ICR.get_var("self"), ICR.get_var("other"))
      when "pointer_malloc" then pointer_malloc_of(p.type, ICR.get_var("size"))
      when "pointer_get"    then pointer_get(ICR.get_var("self"))
      when "pointer_set"    then pointer_set(ICR.get_var("self"), ICR.get_var("value"))
      when "pointer_add"    then pointer_add(ICR.get_var("self"), ICR.get_var("offset"))
      else
        todo "Primitive #{p.name}"
      end
    end

    private def self.binary(name, type, arg0 : ICRObject, arg1 : ICRObject)
      case name
      when "+"  then ICR.number(arg0.as_number + arg1.as_number)
      when "-"  then ICR.number(arg0.as_number - arg1.as_number)
      when "*"  then ICR.number(arg0.as_number * arg1.as_number)
      when "<"  then ICR.bool(arg0.as_number < arg1.as_number)
      when ">"  then ICR.bool(arg0.as_number > arg1.as_number)
      when "!=" then ICR.bool(arg0.as_number != arg1.as_number)
      when "==" then ICR.bool(arg0.as_number == arg1.as_number)
      when "<=" then ICR.bool(arg0.as_number <= arg1.as_number)
      when ">=" then ICR.bool(arg0.as_number >= arg1.as_number)
      else
        todo "Primitive binary:#{name}"
      end
    end

    private def self.allocate(type)
      ICRObject.new(ICRType.new(type.not_nil!)) rescue bug "No type to allocate"
    end

    private def self.pointer_malloc_of(pointer_type : Crystal::Type, size : ICRObject)
      generic = ICRType.new(pointer_type).generics["T"]

      size = size.as_uint64 * generic.size
      p = ICRObject.new(ICRType.pointer_of(generic.cr_type))
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
