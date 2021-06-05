module IC
  module Primitives
    def self.call(p : Crystal::Primitive)
      case p.name
      when "allocate"                       then allocate(p.type)
      when "binary"                         then binary(IC.current_function_name, IC.self_var, IC.get_var("other"))
      when "convert"                        then convert(IC.current_function_name, IC.self_var)
      when "unchecked_convert"              then convert(IC.current_function_name, IC.self_var)
      when "pointer_malloc"                 then pointer_malloc(p.type, IC.get_var("size"))
      when "pointer_new"                    then pointer_new(p.type, IC.get_var("address"))
      when "pointer_realloc"                then pointer_realloc(IC.self_var, IC.get_var("size"))
      when "pointer_get"                    then pointer_get(IC.self_var)
      when "pointer_set"                    then pointer_set(IC.self_var, IC.get_var("value"))
      when "pointer_add"                    then pointer_add(IC.self_var, IC.get_var("offset"))
      when "pointer_diff"                   then pointer_diff(IC.self_var, IC.get_var("other"))
      when "pointer_address"                then pointer_address(IC.self_var)
      when "tuple_indexer_known_index"      then tuple_indexer(IC.self_var, p.as(Crystal::TupleIndexer).index)
      when "object_id"                      then object_id(IC.self_var)
      when "object_crystal_type_id"         then object_crystal_type_id(IC.self_var)
      when "class_crystal_instance_type_id" then class_crystal_instance_type_id(IC.self_var)
      when "class"                          then _class(IC.self_var)
      when "symbol_to_s"                    then symbol_to_s(IC.self_var)
      when "enum_value"                     then enum_value(IC.self_var)
      when "enum_new"                       then enum_new(p.type, IC.get_var("value"))
      when "proc_call"                      then proc_call(IC.self_var, IC.primitives_args)
      when "argv"                           then argv(p.type)
      when "argc"                           then argc
        # TODO:
        # build in:
        # * struct_or_union_set (c-struct)
        # * external_var_set (extern-c)
        # * external_var_get (extern-c)
        #
        # other:
        # * throw_info
        # * va_arg
        # * cmpxchg
        # * atomicrmw
        # * fence
        # * store_atomic
      when "load_atomic" then load_atomic(IC.primitives_args[0], IC.primitives_args[1], IC.primitives_args[2])
      else
        todo "Primitive #{p.name}"
      end
    end

    private def self.allocate(type)
      obj = ICObject.new type || bug! "No type to allocate"

      case type
      when Crystal::InstanceVarInitializerContainer
        type.all_instance_vars.each do |name, ivar|
          obj[name] = type.get_instance_var_initializer(name).try &.value.run || IC.nil
        end
      when Crystal::InstanceVarContainer
        type.all_instance_vars.each do |name, ivar|
          obj[name] = IC.nil
        end
      end
      obj
    end

    private def self.binary(name, arg0 : ICObject, arg1 : ICObject)
      # We admit here that arg0 and arg1 are always Number, unless for
      # "!=" and "==" in which these can be Bool, Char, or Symbol
      # and "<",">","<=",">=" in which these can be Char.
      case name
      when "+"          then IC.number(arg0.as_number + arg1.as_number)
      when "-"          then IC.number(arg0.as_number - arg1.as_number)
      when "*"          then IC.number(arg0.as_number * arg1.as_number)
      when "/"          then IC.number(arg0.as_number / arg1.as_number)
      when "!="         then IC.bool(arg0.as_number != arg1.as_number)
      when "=="         then IC.bool(arg0.as_number == arg1.as_number)
      when "<"          then IC.bool(arg0.as_number < arg1.as_number)
      when ">"          then IC.bool(arg0.as_number > arg1.as_number)
      when "<="         then IC.bool(arg0.as_number <= arg1.as_number)
      when ">="         then IC.bool(arg0.as_number >= arg1.as_number)
      when "&+"         then IC.number(arg0.as_integer &+ arg1.as_integer)
      when "&-"         then IC.number(arg0.as_integer &- arg1.as_integer)
      when "&*"         then IC.number(arg0.as_integer &* arg1.as_integer)
      when "|"          then IC.number(arg0.as_integer | arg1.as_integer)
      when "&"          then IC.number(arg0.as_integer & arg1.as_integer)
      when "^"          then IC.number(arg0.as_integer ^ arg1.as_integer)
      when "unsafe_shr" then IC.number(arg0.as_integer.unsafe_shr arg1.as_integer)
      when "unsafe_shl" then IC.number(arg0.as_integer.unsafe_shl arg1.as_integer)
      when "unsafe_div" then IC.number(arg0.as_integer.unsafe_div arg1.as_integer)
      when "unsafe_mod" then IC.number(arg0.as_integer.unsafe_mod arg1.as_integer)
      when "fdiv"       then IC.number(arg0.as_float.fdiv arg1.as_number)
      else
        bug! "Unexpected Primitive binary: #{name}"
      end
      # TODO rescue OverflowError
    end

    private def self.convert(name, arg : ICObject)
      {% begin %}
        case name
        when "unsafe_chr" then IC.char(arg.as_integer.unsafe_chr)
        when "ord"        then IC.number(arg.as_char.ord)
          {% for sufix in %w(i u f i8 i16 i32 i64 i128 u8 u16 u32 u64 u128 f32 f64) %}
            when "to_{{sufix.id}}"
              IC.number(arg.as_number.to_{{sufix.id}})
            when "to_{{sufix.id}}!"
              IC.number(arg.as_number.to_{{sufix.id}}!)
          {% end %}
        else
          bug! "Unexpected Primitive convert: #{name}"
        end
      {% end %}
      # TODO rescue OverflowError
    end

    private def self.pointer_malloc(type : Type, size : ICObject)
      size = size.as_number.to_u64 * type.pointer_element_size

      IC.pointer(type, address: Pointer(Byte).malloc(size).address)
    end

    private def self.pointer_new(type : Type, address : ICObject)
      IC.pointer(type, address: address.as_number.to_u64)
    end

    private def self.pointer_realloc(p : ICObject, size : ICObject)
      src = Pointer(Byte).new(p.as_uint64)
      size = size.as_number.to_u64 * p.type.pointer_element_size

      IC.pointer(p.type, address: src.realloc(size).address)
    end

    private def self.pointer_set(p : ICObject, value : ICObject)
      type = p.type.pointer_type_var
      dst = Pointer(Byte).new(p.as_uint64)

      type.write value, to: dst
    end

    private def self.pointer_get(p : ICObject)
      type = p.type.pointer_type_var
      src = Pointer(Byte).new(p.as_uint64)

      type.read from: src
    end

    private def self.pointer_add(p : ICObject, x : ICObject)
      new_p = ICObject.new(p.type)
      new_p.as_uint64 = p.as_uint64 + x.as_int32*p.type.pointer_element_size
      new_p
    end

    private def self.pointer_diff(p : ICObject, other : ICObject)
      size = p.type.pointer_element_size
      addr1 = p.as_uint64
      addr2 = other.as_uint64
      if addr1 > addr2
        IC.number(((addr1 - addr2)//size).to_i64)
      else
        IC.number(-((addr2 - addr1)//size).to_i64)
      end
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
      IC.number(IC.type_id(obj.type))
    end

    private def self.class_crystal_instance_type_id(obj : ICObject)
      IC.number(IC.type_id(IC.type_from_id(obj.as_int32)))
    end

    private def self._class(obj : ICObject)
      IC.class(obj.type.metaclass)
    end

    private def self.symbol_to_s(obj : ICObject)
      IC.string(IC.symbol_from_value(obj.as_int32))
    end

    private def self.enum_value(obj : ICObject)
      IC.number(obj.enum_value)
    end

    private def self.enum_new(type : Type, value : ICObject)
      IC.enum(type.as(Crystal::EnumType), value.as_number)
    end

    private def self.proc_call(proc : ICObject, args : Array(ICObject))
      proc.as_proc.call(args)
    end

    private def self.argv(type : Type)
      IC.pointer(type, address: ARGV_UNSAFE.address)
    end

    private def self.argc
      IC.number(ARGC_UNSAFE)
    end

    private def self.load_atomic(p : ICObject, ordering : ICObject, volatile : ICObject)
      # Temporary alternative:
      pointer_get(p)

      # ptr = Pointer(Void).new(p.as_uint64)
      # if (v=IC.symbol_from_value(ordering.as_int32)) != "sequentially_consistent"
      #   todo "Atomic Ordering :#{v}"
      # end
      # volatile = volatile.as_bool

      # result =
      # if volatile
      #   Atomic::Ops.load(ptr, :sequentially_consistent, true)
      # else
      #   Atomic::Ops.load(ptr, :sequentially_consistent, false)
      # end

      # ICObject.new(p.type.pointer_type_var, address: result)
    end
  end
end
