module IC
  struct ICObject
    def enum_value
      bug! "Trying to read enum value on a non-enum type #{@type}" unless (t = @type).is_a? Crystal::EnumType

      case k = t.base_type.kind
      when :i8   then as_int8
      when :u8   then as_uint8
      when :i16  then as_int16
      when :u16  then as_uint16
      when :i32  then as_int32
      when :u32  then as_uint32
      when :i64  then as_int64
      when :u64  then as_uint64
      when :i128 then todo "Enum to #{k}"
      when :u128 then todo "Enum to #{k}"
      else            bug! "Unexpected enum number kind #{k}"
      end
    end

    def enum_name
      bug! "Trying to read enum value on a non-enum type #{@type}" unless @type.is_a? Crystal::EnumType

      val = self.enum_value
      @type.types.each do |member_name, member|
        member_name
        const = member.as(Crystal::Const)
        if val == const.value.as(Crystal::NumberLiteral).integer_value
          return member_name
        end
      end
      "#{@type}:#{val}"
    end

    # Treat this ICObject as Int32, UInt64,..
    # Used by primitives.
    {% for t in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64 Bool Char String) %}
      def as_{{t.downcase.id}}
        @address.as({{t.id}}*).value
      end

      def as_{{t.downcase.id}}=(value : {{t.id}})
        @address.as({{t.id}}*).value = value
      end
    {% end %}

    def as!(type : T.class) : T forall T
      @address.as(T*).value
    end

    def as_integer
      unless (t = @type).is_a? Crystal::IntegerType
        bug! "Trying to read #{t} as Int"
      end

      case t.kind
      when :i8   then self.as_int8
      when :u8   then self.as_uint8
      when :i16  then self.as_int16
      when :u16  then self.as_uint16
      when :i32  then self.as_int32
      when :u32  then self.as_uint32
      when :i64  then self.as_int64
      when :u64  then self.as_uint64
      when :i128 then todo "#{t.kind} as number"
      when :u128 then todo "#{t.kind} as number"
      else
        bug! "Unexpected Number kind #{t.kind}"
      end
    end

    def as_float
      unless (t = @type).is_a? Crystal::FloatType
        bug! "Trying to read #{t} as Float"
      end

      case t.kind
      when :f32 then self.as_float32
      when :f64 then self.as_float64
      else
        bug! "Unexpected Float Number kind #{t.kind}"
      end
    end

    def as_number : Number
      case @type
      when Crystal::IntegerType                   then self.as_integer
      when Crystal::FloatType                     then self.as_float
      when Crystal::BoolType                      then self.as_bool ? 1 : 0
      when Crystal::SymbolType, Crystal::CharType then self.as_int32
      else
        bug! "Trying to read #{@type} as a number"
      end
    end

    def as_proc
      @address.as(Proc(Array(ICObject), ICObject)*).value
    end

    def as_proc=(proc)
      @address.as(Proc(Array(ICObject), ICObject)*).value = proc
    end

    def as_va_arg
      if @type.pointer?
        as_uint64
      else
        as_number.to_u64
      end
    end

    # Gives a string representation of this object.
    def result : String
      return "∅" if @address.null?

      ICObject.result(self.unboxed)
    rescue IC::Error
      return "∅"
    end

    def self.result(value)
      return "∅" if value.type.reference? && value.data.null?

      result =
        case t = value.type
        when Crystal::IntegerType, Crystal::FloatType
          case t.kind
          when :i8   then "#{value.as_int8.to_s.underscored}_i8"
          when :u8   then "#{value.as_uint8.to_s.underscored}_u8"
          when :i16  then "#{value.as_int16.to_s.underscored}_i16"
          when :u16  then "#{value.as_uint16.to_s.underscored}_u16"
          when :i32  then "#{value.as_int32.to_s.underscored}"
          when :u32  then "#{value.as_uint32.to_s.underscored}_u32"
          when :i64  then "#{value.as_int64.to_s.underscored}_i64"
          when :u64  then "0x#{value.as_uint64.to_s(16)}"
          when :f32  then "#{value.as_float32.to_s.underscored}_f32"
          when :f64  then "#{value.as_float64.to_s.underscored}"
          when :i128 then todo "#{t.kind} as number"
          when :u128 then todo "#{t.kind} as number"
          end
        when Crystal::BoolType   then value.as_bool.inspect
        when Crystal::CharType   then value.as_char.inspect
        when Crystal::SymbolType then ":#{IC.symbol_from_value(value.as_int32)}"
        when Crystal::NilType    then "nil"
        when Crystal::EnumType   then "#{value.enum_name}"
        when Crystal::TupleInstanceType
          entries = value.type.map_ivars { |name| value[name].result }
          "{#{entries.join(", ")}}"
        when Crystal::NamedTupleInstanceType
          entries = value.type.map_ivars { |name| "#{t.entries[name.to_i].name}: #{value[name].result}" }
          "{#{entries.join(", ")}}"
          # when .array?
        when .string?    then value.as_string.inspect
        when .metaclass? then t.to_s.chomp(".class").chomp(":Module")
        when .reference? then "#<#{t}:0x#{value.as_uint64.to_s(16)}>"
        when .struct?    then "#<#{t}>"
        end
      result || "??? #{t}"
    end
  end
end

module IC
  # Creates the corresponding literals from values:

  def self.nop : ICObject
    ICObject.nop
  end

  def self.nil : ICObject
    ICObject.create(IC.program.nil)
  end

  def self.bool(value : Bool) : ICObject
    obj = ICObject.create(IC.program.bool)
    obj.as_bool = value
    obj
  end

  {% for t in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64) %}
    def self.number(value : {{t.id}}) : ICObject
      obj = ICObject.create(IC.program.{{t.downcase.id}})
      obj.as_{{t.downcase.id}} = value
      obj
    end
  {% end %}

  def self.number(value)
    todo "#{value.class} to ICObject"
  end

  def self.char(value : Char) : ICObject
    obj = ICObject.create(IC.program.char)
    obj.as_char = value
    obj
  end

  # obj.raw -> ref -> | TYPE_ID (4)
  #                   | @bytesize (4)
  #                   | @length (4)
  #                   | @c    (@bytesize times)
  #                   | ...
  def self.string(value : String) : ICObject
    obj = ICObject.create(IC.program.string).allocate
    (obj.data + 4).as(Int32*).value = value.@bytesize
    (obj.data + 8).as(Int32*).value = value.@length
    (obj.data + 12).as(UInt8*).copy_from(pointerof(value.@c), value.@bytesize)
    obj
  end

  def self.pointer(pointer_type : Type, address : UInt64) : ICObject
    obj = ICObject.create(pointer_type)
    obj.as_uint64 = address
    obj
  end

  def self.pointer_of(type : Type, address : UInt64) : ICObject
    IC.pointer(IC.program.pointer_of(type), address)
  end

  def self.symbol(value : String) : ICObject
    obj = ICObject.create(IC.program.symbol)
    obj.as_int32 = IC.symbol_value(value)
    obj
  end

  def self.tuple(type : Type, elements : Array(ICObject)) : ICObject
    obj = ICObject.create(type)
    elements.each_with_index do |e, i|
      obj[i.to_s] = e
    end
    obj
  end

  def self.class(type : Type) : ICObject
    type = type.devirtualize

    bug! "Trying to create a class or a module from a non metaclass type (#{type.class})" unless type.responds_to? :instance_type

    obj = ICObject.create(type)
    obj.as_int32 = IC.type_id(type.instance_type, instance: false)
    obj
  end

  def self.enum(type : Crystal::EnumType, value) : ICObject
    obj = ICObject.create(type)
    case k = type.base_type.kind
    when :i8   then obj.as_int8 = value.to_i8
    when :u8   then obj.as_uint8 = value.to_u8
    when :i16  then obj.as_int16 = value.to_i16
    when :u16  then obj.as_uint16 = value.to_u16
    when :i32  then obj.as_int32 = value.to_i32
    when :u32  then obj.as_uint32 = value.to_u32
    when :i64  then obj.as_int64 = value.to_i64
    when :u64  then obj.as_uint64 = value.to_u64
    when :i128 then todo "Enum from #{k}"
    when :u128 then todo "Enum from #{k}"
    end
    obj
  end

  def self.enum_from_symbol(type : Crystal::EnumType, symbol : ICObject) : ICObject
    name = IC.symbol_from_value(symbol.as_int32)
    const = type.find_member(name)
    bug! "Cannot create a enum #{type} from the symbol #{name}" unless const

    value = const.value.as(Crystal::NumberLiteral).integer_value
    IC.enum(type, value)
  end

  # def self.uninitialized(type : Type) : ObjectView
  #   Literal.new(type, initialized: false).view
  # end

  def self.proc(type : Type, & : -> Proc(Array(ICObject), ICObject)) : ICObject
    obj = ICObject.create(type)
    obj.as_proc = yield 42u64 # proc_id DEAD CODE?? #obj.object_id
    obj
  end
end

class String
  # Add underscores to this number string
  #
  # "10000000"    => "10_000_000"
  # "-1000"       => "-1_000"
  # "-1000.12345" => "-1_000.123_45"
  def underscored
    return self if self.in? "Infinity", "-Infinity"

    String.build do |io|
      parts = self.split('.')
      parts.each_with_index do |str, part|
        str.each_char_with_index do |c, i|
          i = (part == 0) ? (str.size - 1 - i) : i + 1

          io << c
          if i % 3 == 0 && (0 != i != str.size) && c != '-'
            io << '_'
          end
        end
        io << '.' unless part == parts.size - 1
      end
    end
  end
end
