module ICR
  module Primitives
    def self.call(p : Crystal::Primitive)
      case p.name
      when "allocate"                  then allocate(p.type)
      when "binary"                    then binary(ICR.current_function_name, p.type, ICR.get_var("self"), ICR.get_var("other"))
      when "pointer_malloc"            then pointer_malloc(p.type, ICR.get_var("size"))
      when "pointer_new"               then pointer_new(p.type, ICR.get_var("address"))
      when "pointer_get"               then pointer_get(ICR.get_var("self"))
      when "pointer_set"               then pointer_set(ICR.get_var("self"), ICR.get_var("value"))
      when "pointer_add"               then pointer_add(ICR.get_var("self"), ICR.get_var("offset"))
      when "pointer_address"           then pointer_address(ICR.get_var("self"))
      when "tuple_indexer_known_index" then tuple_indexer(ICR.get_var("self"), p.as(Crystal::TupleIndexer).index)
      when "object_id"                 then object_id(ICR.get_var("self"))
      when "object_crystal_type_id"    then object_crystal_type_id(ICR.get_var("self"))
      when "class"                     then _class(ICR.get_var("self"))
      else
        todo "Primitive #{p.name}"
      end
    end

    private def self.allocate(type)
      ICRObject.new ICRType.new type || bug! "No type to allocate"
    end

    private def self.binary(name, type, arg0 : ICRObject, arg1 : ICRObject)
      case name
      when "+"  then ICR.number(arg0.as_number + arg1.as_number)
      when "-"  then ICR.number(arg0.as_number - arg1.as_number)
      when "*"  then ICR.number(arg0.as_number * arg1.as_number)
      when "/"  then ICR.number(arg0.as_number / arg1.as_number)
      when "<"  then ICR.bool(arg0.as_number < arg1.as_number)
      when ">"  then ICR.bool(arg0.as_number > arg1.as_number)
      when "!=" then ICR.bool(arg0.as_number != arg1.as_number)
      when "==" then ICR.bool(arg0.as_number == arg1.as_number)
      when "<=" then ICR.bool(arg0.as_number <= arg1.as_number)
      when ">=" then ICR.bool(arg0.as_number >= arg1.as_number)
      else
        todo "Primitive binary: #{name}"
      end
      # TODO rescue OverflowError
    end

    private def self.pointer_malloc(pointer_type : Crystal::Type, size : ICRObject)
      type_var = ICRType.new(pointer_type).type_vars["T"]

      size = size.as_number.to_u64 * type_var.size
      p = ICRObject.new(ICRType.pointer_of(type_var.cr_type))
      p.as_uint64 = Pointer(Byte).malloc(size).address
      p
    end

    private def self.pointer_new(pointer_type : Crystal::Type, address : ICRObject)
      type_var = ICRType.new(pointer_type).type_vars["T"]

      p = ICRObject.new(ICRType.pointer_of(type_var.cr_type))
      p.as_uint64 = address.as_number.to_u64
      p
    end

    private def self.pointer_set(p : ICRObject, value : ICRObject)
      dst = Pointer(Byte).new(p.as_uint64)
      type = p.type.type_vars["T"]

      type.write value, to: dst
    end

    private def self.pointer_get(p : ICRObject)
      type = p.type.type_vars["T"]
      src = Pointer(Byte).new(p.as_uint64)

      type.read from: src
    end

    private def self.pointer_add(p : ICRObject, x : ICRObject)
      new_p = ICRObject.new(p.type)
      new_p.as_uint64 = p.as_uint64 + x.as_int32*p.type.type_vars["T"].size
      new_p
    end

    private def self.pointer_address(p : ICRObject)
      ICR.number(p.as_uint64)
    end

    private def self.tuple_indexer(tuple : ICRObject, index : Int32 | Range(Int32, Int32))
      if index.is_a? Int32
        tuple[index.to_s]
      else
        todo "Tuple indexer with range index"
      end
    end

    private def self.object_id(obj : ICRObject)
      ICR.number(obj.as_uint64)
    end

    private def self.object_crystal_type_id(obj : ICRObject)
      ICR.number(ICR.get_crystal_type_id(obj.type.cr_type))
    end

    private def self._class(obj : ICRObject)
      ICR.class(obj.type.cr_type.metaclass)
    end
  end
end
