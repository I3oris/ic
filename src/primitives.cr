module IC
  module Primitives
    def self.call(p : Crystal::Primitive)
      case p.name
      when "allocate"                       then allocate(p.type)
      when "binary"                         then binary(IC.current_function_name, p.type, IC.get_var("self"), IC.get_var("other"))
      when "pointer_malloc"                 then pointer_malloc(p.type, IC.get_var("size"))
      when "pointer_new"                    then pointer_new(p.type, IC.get_var("address"))
      when "pointer_get"                    then pointer_get(IC.get_var("self"))
      when "pointer_set"                    then pointer_set(IC.get_var("self"), IC.get_var("value"))
      when "pointer_add"                    then pointer_add(IC.get_var("self"), IC.get_var("offset"))
      when "pointer_address"                then pointer_address(IC.get_var("self"))
      when "tuple_indexer_known_index"      then tuple_indexer(IC.get_var("self"), p.as(Crystal::TupleIndexer).index)
      when "object_id"                      then object_id(IC.get_var("self"))
      when "object_crystal_type_id"         then object_crystal_type_id(IC.get_var("self"))
      when "class_crystal_instance_type_id" then class_crystal_instance_type_id(IC.get_var("self"))
      when "class"                          then _class(IC.get_var("self"))
      else
        todo "Primitive #{p.name}"
      end
    end

    private def self.allocate(type)
      ICObject.new ICType.new type || bug! "No type to allocate"
    end

    private def self.binary(name, type, arg0 : ICObject, arg1 : ICObject)
      case name
      when "+"  then IC.number(arg0.as_number + arg1.as_number)
      when "-"  then IC.number(arg0.as_number - arg1.as_number)
      when "*"  then IC.number(arg0.as_number * arg1.as_number)
      when "/"  then IC.number(arg0.as_number / arg1.as_number)
      when "<"  then IC.bool(arg0.as_number < arg1.as_number)
      when ">"  then IC.bool(arg0.as_number > arg1.as_number)
      when "<=" then IC.bool(arg0.as_number <= arg1.as_number)
      when ">=" then IC.bool(arg0.as_number >= arg1.as_number)
      when "!=" then IC.bool(arg0.as_number != arg1.as_number)
      when "==" then IC.bool(arg0.as_number == arg1.as_number)
      else
        todo "Primitive binary: #{name}"
      end
      # TODO rescue OverflowError
    end

    private def self.pointer_malloc(pointer_type : Crystal::Type, size : ICObject)
      type_var = ICType.new(pointer_type).type_vars["T"]

      size = size.as_number.to_u64 * type_var.size
      p = ICObject.new(ICType.pointer_of(type_var.cr_type))
      p.as_uint64 = Pointer(Byte).malloc(size).address
      p
    end

    private def self.pointer_new(pointer_type : Crystal::Type, address : ICObject)
      type_var = ICType.new(pointer_type).type_vars["T"]

      p = ICObject.new(ICType.pointer_of(type_var.cr_type))
      p.as_uint64 = address.as_number.to_u64
      p
    end

    private def self.pointer_set(p : ICObject, value : ICObject)
      dst = Pointer(Byte).new(p.as_uint64)
      type = p.type.type_vars["T"]

      type.write value, to: dst
    end

    private def self.pointer_get(p : ICObject)
      type = p.type.type_vars["T"]
      src = Pointer(Byte).new(p.as_uint64)

      type.read from: src
    end

    private def self.pointer_add(p : ICObject, x : ICObject)
      new_p = ICObject.new(p.type)
      new_p.as_uint64 = p.as_uint64 + x.as_int32*p.type.type_vars["T"].size
      new_p
    end

    private def self.pointer_address(p : ICObject)
      IC.number(p.as_uint64)
    end

    private def self.tuple_indexer(tuple : ICObject, index : Int32 | Range(Int32, Int32))
      if index.is_a? Int32
        tuple[index.to_s]
      else
        todo "Tuple indexer with range index"
      end
    end

    private def self.object_id(obj : ICObject)
      IC.number(obj.as_uint64)
    end

    private def self.object_crystal_type_id(obj : ICObject)
      IC.number(IC.type_id(obj.type.cr_type))
    end

    private def self.class_crystal_instance_type_id(obj : ICObject)
      IC.number(IC.type_id(IC.type_from_id(obj.as_int32)))
    end

    private def self._class(obj : ICObject)
      IC.class(obj.type.cr_type.metaclass)
    end
  end
end
