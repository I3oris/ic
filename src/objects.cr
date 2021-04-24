module IC
  # ICObject are transmitted through the AST Tree, and represents Object created with IC
  #
  # There are constituted of a ICType and a pointer on the binary representation of the object (`raw`)
  # i.e for a Int32, raw will be a pointer on 4 bytes.
  #
  # For classes, raw will be a pointer on 8 bytes (address), pointing itself on the classes size.
  #
  # The ICType will give information of how to treat the raw binary.
  #
  # `@type` is always the **runtime* type of the object, and cannot be virtual or an union.
  class ICObject
    getter type : ICType
    getter raw : Pointer(Byte)
    getter? nop = false

    def initialize(@type)
      if !@type.instantiable?
        bug! "Cannot create a object with a runtime union or virtual type (#{@type.cr_type})"
      end

      if @type.reference_like?
        raw = Pointer(Byte*).malloc
        if @type.cr_type.nil_type?
          # raw -> null
          raw.value = Pointer(Byte).null
        else
          # raw -> ref -> | TYPE_ID (4)
          #               | @ivar 1
          #               | @ivar 2
          #               | ...
          raw.value = Pointer(Byte).malloc(@type.class_size)
          raw.value.as(Int32*).value = IC.type_id(@type.cr_type)
        end
        @raw = raw.as(Byte*)
      else
        # raw -> | @ivar 1
        #        | @ivar 2
        #        | ...
        @raw = Pointer(Byte).malloc(@type.size)
      end
    end

    def initialize(@type, from @raw)
      if !@type.instantiable?
        bug! "Cannot create a object with a runtime union or virtual type (#{@type.cr_type})"
      end
    end

    def initialize(@type, uninitialized? : Bool)
      @raw = Pointer(Byte).malloc(@type.size)
    end

    def initialize(@nop : Bool)
      @type = ICType.nil
      @raw = Pointer(Byte).null
    end

    # Returns the pointer on the data of this object:
    # raw -> data (for struct)
    # raw -> ref -> data (for classes)
    def data
      if !@type.reference_like?
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

    # Falsey if is nil, false, Pointer.null.
    def falsey?
      t = @type.cr_type
      t.nil_type? || (t.bool_type? && self.as_bool == false) # || is_null_pointer?
    end

    def cast(from : Crystal::Type?, to : Crystal::Type?)
      bug! "Cast from #{@type.cr_type} failed" if from.nil? || to.nil?
      if @type.cr_type.pointer?
        # Pointer cast seems never fail
        return ICObject.new(ICType.new(to), from: @raw)
      end

      if @type.cr_type <= to
        self
      else
        nil
      end
    end

    def is_a(type : Crystal::Type?)
      bug! "is_a? #{@type.cr_type} failed" if type.nil?
      @type.cr_type <= type
    end

    # Returns a new ICObject(Pointer) pointing on the raw data of this object
    def pointerof_self
      p = ICObject.new(ICType.pointer_of(@type.cr_type))
      p.as_uint64 = @raw.address
      p
    end

    # Returns a new ICObject(Pointer) pointing on the offset of *ivar*
    def pointerof(*, ivar : String)
      offset, type = @type.offset_and_type_of(ivar)
      p = ICObject.new(ICType.pointer_of(type.cr_type))
      p.as_uint64 = (self.data + offset).address
      p
    end

    # Gives a string representation used by IC to display the result of an instruction.
    def result : String
      result =
        case t = @type.cr_type
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
        when Crystal::TupleInstanceType
          entries = @type.map_ivars { |name| self[name].result }
          "{#{entries.join(", ")}}"
        when Crystal::NamedTupleInstanceType
          entries = @type.map_ivars { |name| "#{t.entries[name.to_i].name}: #{self[name].result}" }
          "{#{entries.join(", ")}}"
          # when .array?
        when .string?         then as_string.inspect
        when .metaclass?      then t.to_s.chomp(".class").chomp(":Module")
        when .reference_like? then "#<#{t}:0x#{as_uint64.to_s(16)}>"
        when .struct?         then "#<#{t}>"
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

    def as_number : Number
      ret =
        case t = @type.cr_type
        when Crystal::IntegerType
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
          end
        when Crystal::FloatType
          case t.kind
          when :f32 then self.as_float32
          when :f64 then self.as_float64
          end
        when Crystal::BoolType
          self.as_bool ? 1 : 0
        when Crystal::SymbolType, Crystal::CharType
          self.as_int32
        end
      ret || bug! "Trying to read #{t} as a number"
    end
  end

  # Creates the corresponding ICObject from values:

  def self.nop
    ICObject.new(nop: true)
  end

  def self.nil
    ICObject.new(ICType.nil)
  end

  def self.bool(value : Bool)
    obj = ICObject.new(ICType.bool)
    obj.as_bool = value
    obj
  end

  {% for t in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64) %}
    def self.number(value : {{t.id}})
      obj = ICObject.new(ICType.{{t.downcase.id}})
      obj.as_{{t.downcase.id}} = value
      obj
    end
  {% end %}

  def self.number(value)
    todo "#{value.class} to ICObject"
  end

  def self.char(value : Char)
    obj = ICObject.new(ICType.char)
    obj.as_char = value
    obj
  end

  # obj.raw -> ref -> | TYPE_ID (4)
  #                   | @bytesize (4)
  #                   | @length (4)
  #                   | @c    (@bytesize times)
  #                   | ...
  def self.string(value : String)
    obj = ICObject.new(ICType.string)
    (obj.data + 4).as(Int32*).value = value.@bytesize
    (obj.data + 8).as(Int32*).value = value.@length
    (obj.data + 12).as(UInt8*).copy_from(pointerof(value.@c), value.@bytesize)
    obj
  end

  def self.symbol(value : String)
    obj = ICObject.new(ICType.new(IC.program.symbol))
    obj.as_int32 = IC.symbol_value(value)
    obj
  end

  def self.tuple(type : Crystal::Type, elements : Array(ICObject))
    obj = ICObject.new(ICType.new(type))
    elements.each_with_index do |e, i|
      obj[i.to_s] = e
    end
    obj
  end

  def self.class(type : Crystal::Type)
    type = type.devirtualize

    bug! "Trying to create a class or a module from a non metaclass type (#{type.class})" unless type.responds_to? :instance_type

    obj = ICObject.new(ICType.new(type))
    obj.as_int32 = IC.type_id(type.instance_type, instance: false)
    obj
  end

  def self.uninitialized(type : Crystal::Type)
    ICObject.new(ICType.new(type), uninitialized?: true)
  end
end

class String
  # Add underscores to this number string
  #
  # "10000000"    => "10_000_000"
  # "-1000"       => "-1_000"
  # "-1000.12345" => "-1_000.123_45"
  def underscored
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
