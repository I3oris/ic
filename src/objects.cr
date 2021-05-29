module IC
  # ICObject are transmitted through the AST Tree, and represents Object created with IC
  #
  # There are constituted of a `Type` and a pointer on the binary representation of the object (`raw`)
  # i.e for a Int32, raw will be a pointer on 4 bytes.
  #
  # For classes, raw will be a pointer on 8 bytes (address), pointing itself on the classes size.
  #
  # The `Type` will give information of how to treat the raw binary.
  #
  # `@type` is always the **runtime* type of the object, and cannot be virtual or an union.
  class ICObject
    getter type : Type
    getter raw : Pointer(Byte)
    getter? nop = false

    def initialize(@type)
      if !@type.instantiable?
        bug! "Cannot create a object with a runtime union or virtual type (#{@type})"
      end

      case @type
      when .nil_type?
        # raw -> null (8)
        raw = Pointer(Byte*).malloc
        raw.value = Pointer(Byte).null
        @raw = raw.as(Byte*)
      when .reference?
        # raw -> ref -> | TYPE_ID (4)
        #               | @ivar 1
        #               | @ivar 2
        #               | ...
        raw = Pointer(Byte*).malloc
        raw.value = Pointer(Byte).malloc(@type.ic_class_size)
        raw.value.as(Int32*).value = IC.type_id(@type)
        @raw = raw.as(Byte*)
      else
        # raw -> | @ivar 1
        #        | @ivar 2
        #        | ...
        @raw = Pointer(Byte).malloc(@type.ic_size)
      end
    end

    def initialize(@type, from @raw)
      if !@type.instantiable?
        bug! "Cannot create a object with a runtime union or virtual type (#{@type})"
      end
    end

    def initialize(@type, uninitialized? : Bool)
      @raw = Pointer(Byte).malloc(@type.ic_size)
    end

    def initialize(@nop : Bool)
      @type = IC.program.nil
      @raw = Pointer(Byte).null
    end

    # Returns the pointer on the data of this object:
    # raw -> data (for struct)
    # raw -> ref -> data (for classes)
    def data
      if !@type.reference?
        @raw
      else
        @raw.as(Byte**).value
      end
    end

    # Read an ivar from this object
    def [](name)
      @type.read_ivar(name, from: self.data)
    end

    # Write an ivar of this object
    def []=(name, value : ICObject)
      @type.write_ivar(name, value, to: self.data)
    end

    def truthy?
      !falsey?
    end

    # Falsey if is nil, false, or null Pointer
    def falsey?
      @type.nil_type? || (@type.bool_type? && self.as_bool == false) || (@type.pointer? && self.as_uint64 == 0u64)
    end

    def cast(from : Type?, to : Type?)
      bug! "Cast from #{@type} failed" if from.nil? || to.nil?
      if @type.pointer?
        # Pointer cast seems never fail
        return ICObject.new(to, from: @raw)
      end

      if @type <= to
        self
      else
        nil
      end
    end

    def is_a(type : Type?)
      bug! ".is_a?(#{@type}) failed" if type.nil?
      @type <= type
    end

    def assign(other : ICObject) : ICObject
      # TODO check if ic_size is not too small
      @raw.copy_from(other.raw, other.type.ic_size)
      @type = other.type
      self
    end

    def copy
      obj = ICObject.new(@type)
      obj.raw.copy_from(@raw, @type.ic_size)
      obj
    end

    # Returns a new ICObject(Pointer) pointing on the raw data of this object
    def pointerof_self
      IC.pointer_of(@type, address: @raw.address)
    end

    # Returns a new ICObject(Pointer) pointing on the offset of *ivar*
    def pointerof(*, ivar : String)
      offset, type = @type.offset_and_type_of(ivar)
      IC.pointer_of(type, address: (self.data + offset).address)
    end

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

    # Gives a string representation used by IC to display the result of an instruction.
    def result : String
      result =
        case t = @type
        when Crystal::IntegerType
          case t.kind
          when :i8   then "#{as_int8.to_s.underscored}_i8"
          when :u8   then "#{as_uint8.to_s.underscored}_u8"
          when :i16  then "#{as_int16.to_s.underscored}_i16"
          when :u16  then "#{as_uint16.to_s.underscored}_u16"
          when :i32  then as_int32.to_s.underscored
          when :u32  then "#{as_uint32.to_s.underscored}_u32"
          when :i64  then "#{as_int64.to_s.underscored}_i64"
          when :u64  then "0x#{as_uint64.to_s(16)}"
          when :i128 then todo "#{t.kind} as number"
          when :u128 then todo "#{t.kind} as number"
          end
        when Crystal::FloatType
          case t.kind
          when :f32 then "#{as_float32.to_s.underscored}_f32"
          when :f64 then as_float64.to_s.underscored
          end
        when Crystal::BoolType   then as_bool.inspect
        when Crystal::CharType   then as_char.inspect
        when Crystal::SymbolType then ":#{IC.symbol_from_value(as_int32)}"
        when Crystal::NilType    then "nil"
        when Crystal::EnumType   then "#{enum_name}"
        when Crystal::TupleInstanceType
          entries = @type.map_ivars { |name| self[name].result }
          "{#{entries.join(", ")}}"
        when Crystal::NamedTupleInstanceType
          entries = @type.map_ivars { |name| "#{t.entries[name.to_i].name}: #{self[name].result}" }
          "{#{entries.join(", ")}}"
          # when .array?
        when .string?    then as_string.inspect
        when .metaclass? then t.to_s.chomp(".class").chomp(":Module")
        when .reference? then "#<#{t}:0x#{as_uint64.to_s(16)}>"
        when .struct?    then "#<#{t}>"
        end
      result || "??? #{t}"
    end

    # Treat this ICObject as Int32,UInt64,..
    # Used by primitives.
    {% for t in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64 Bool Char String) %}
      def as_{{t.downcase.id}}
        @raw.as({{t.id}}*).value
      end

      def as_{{t.downcase.id}}=(value : {{t.id}})
        @raw.as({{t.id}}*).value = value
      end
    {% end %}

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
      @raw.as(Proc(Array(ICObject), ICObject)*).value
    end

    def as_proc=(proc)
      @raw.as(Proc(Array(ICObject), ICObject)*).value = proc
    end
  end

  # Creates the corresponding ICObject from values:

  def self.nop
    ICObject.new(nop: true)
  end

  def self.nil
    ICObject.new(IC.program.nil)
  end

  def self.bool(value : Bool)
    obj = ICObject.new(IC.program.bool)
    obj.as_bool = value
    obj
  end

  {% for t in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64) %}
    def self.number(value : {{t.id}})
      obj = ICObject.new(IC.program.{{t.downcase.id}})
      obj.as_{{t.downcase.id}} = value
      obj
    end
  {% end %}

  def self.number(value)
    todo "#{value.class} to ICObject"
  end

  def self.char(value : Char)
    obj = ICObject.new(IC.program.char)
    obj.as_char = value
    obj
  end

  # obj.raw -> ref -> | TYPE_ID (4)
  #                   | @bytesize (4)
  #                   | @length (4)
  #                   | @c    (@bytesize times)
  #                   | ...
  def self.string(value : String)
    obj = ICObject.new(IC.program.string)
    (obj.data + 4).as(Int32*).value = value.@bytesize
    (obj.data + 8).as(Int32*).value = value.@length
    (obj.data + 12).as(UInt8*).copy_from(pointerof(value.@c), value.@bytesize)
    obj
  end

  def self.pointer(pointer_type : Type, address : UInt64)
    obj = ICObject.new(pointer_type)
    obj.as_uint64 = address
    obj
  end

  def self.pointer_of(type : Type, address : UInt64)
    IC.pointer(IC.program.pointer_of(type), address)
  end

  def self.symbol(value : String)
    obj = ICObject.new(IC.program.symbol)
    obj.as_int32 = IC.symbol_value(value)
    obj
  end

  def self.tuple(type : Type, elements : Array(ICObject))
    obj = ICObject.new(type)
    elements.each_with_index do |e, i|
      obj[i.to_s] = e
    end
    obj
  end

  def self.class(type : Type)
    type = type.devirtualize

    bug! "Trying to create a class or a module from a non metaclass type (#{type.class})" unless type.responds_to? :instance_type

    obj = ICObject.new(type)
    obj.as_int32 = IC.type_id(type.instance_type, instance: false)
    obj
  end

  def self.enum(type : Crystal::EnumType, value)
    obj = ICObject.new(type)
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

  def self.enum_from_symbol(type : Crystal::EnumType, symbol : ICObject)
    name = IC.symbol_from_value(symbol.as_int32)
    const = type.find_member(name)
    bug! "Cannot create a enum #{type} from the symbol #{name}" unless const

    value = const.value.as(Crystal::NumberLiteral).integer_value
    IC.enum(type, value)
  end

  def self.uninitialized(type : Type)
    ICObject.new(type, uninitialized?: true)
  end

  def self.proc(type : Type, & : -> Proc(Array(ICObject), ICObject))
    obj = ICObject.new(type)
    obj.as_proc = yield obj.object_id
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
