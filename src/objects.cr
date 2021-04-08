module ICR
  # ICRObject are transmitted through the AST Tree, and represents Object created with icr
  #
  # There are constituted of a ICRType and a pointer on the binary representation of the object (`raw`)
  # i.e for a Int32, raw will be a pointer on 4 bytes.
  #
  # For classes, raw will be a pointer on 8 bytes (address), pointing itself on the classes size.
  #
  # The ICRType will give information of how to treat the raw binary.
  class ICRObject
    getter type : ICRType
    getter raw : Pointer(Byte)
    getter dont_collect : Pointer(Byte)? = nil
    protected setter raw

    def initialize(@type)
      if @type.struct?
        # raw -> | @ivar1
        #        | @ivar2
        #        | ...
        @raw = Pointer(Byte).malloc(@type.size)
      else
        # raw -> ref -> | TYPE_ID (4)
        #               | @ivar 1
        #               | @ivar 2
        #               | ...
        @raw = Pointer(Byte).malloc(8)
        ref = Pointer(Byte).malloc(@type.class_size)
        @dont_collect = ref
        @raw.as(UInt64*).value = ref.address
      end
    end

    # raw -> ref -> | TYPE_ID (4)
    #               | @bytesize (4)
    #               | @length (4)
    #               | @c    (@bytesize times)
    #               | ...
    def initialize(*, from_string str : String)
      @type = ICRType.string
      @raw = Pointer(Byte).malloc(8)

      bs = str.bytesize
      len = str.@length

      ref = Pointer(Byte).malloc(String::HEADER_SIZE + bs + 1)
      (ref + 4).as(Int32*).value = bs
      (ref + 8).as(Int32*).value = len
      (ref + String::HEADER_SIZE).copy_from(pointerof(str.@c), bs)
      @dont_collect = ref
      @raw.as(UInt64*).value = ref.address
    end

    # Returns the pointer on the data of this object:
    # @raw -> data (for struct)
    # @raw -> ref -> data (for classes)
    def data
      if @type.struct?
        @raw
      else
        addr = @raw.as(UInt64*).value
        ref = Pointer(Byte).new(addr)
        ref
      end
    end

    # Read an ivar from this object
    def [](name)
      obj = ICRObject.new(@type.type_of(name))
      @type.read_ivar(name, self.data, obj.raw)
      obj
    end

    # Write an ivar of this object
    def []=(name, value : ICRObject)
      @type.write_ivar(name, value.raw, self.data)
      value
    end

    def cast_to(type : Crystal::Type?)
      bug "Cast from #{@type.cr_type} failed" if type.nil?

      # TODO handle upcast and downcast
      obj = ICRObject.new(ICRType.new(type))
      obj.raw = @raw
      obj
    end

    # Returns a new ICRObject(Pointer) pointing on the raw data of this object
    def pointerof_self
      p = ICRObject.new(ICRType.pointer_of(@type.cr_type))
      p.as_uint64 = @raw.address
      p
    end

    # Returns a new ICRObject(Pointer) pointing on the offset of *ivar*
    def pointerof(*, ivar : String)
      offset, type = @type.offset_and_type_of(ivar)
      p = ICRObject.new(ICRType.pointer_of(type.cr_type))
      p.as_uint64 = (self.data + offset).address
      p
    end

    def truthy?
      !falsey?
    end

    # Falsey if is nil, false, Pointer.null.
    def falsey?
      t = @type.cr_type
      t.nil_type? || (t.bool_type? && self.as_bool == false) # || is_null_pointer?
    end

    # Gives a string representation used by icr to display the result of an instruction.
    def result
      case t = @type.cr_type.to_s # TODO avoid the string transformation
      when "Int8"    then "#{as_int8.to_s.underscored}i8"
      when "UInt8"   then "#{as_uint8.to_s.underscored}u8"
      when "Int16"   then "#{as_int16.to_s.underscored}i16"
      when "UInt16"  then "#{as_uint16.to_s.underscored}u16"
      when "Int32"   then as_int32.to_s.underscored
      when "UInt32"  then "#{as_uint32.to_s.underscored}u32"
      when "Int64"   then "#{as_int64.to_s.underscored}i64"
      when "UInt64"  then "#{as_uint64.to_s.underscored}u64"
      when "Float32" then "#{as_float32.to_s.underscored}f32"
      when "Float64" then as_float64.to_s.underscored
      when "Bool"    then as_bool.inspect
      when "Char"    then as_char.inspect
      when "String"  then as_string.inspect
      when "Symbol"  then ":#{ICR.get_symbol_from_value(as_int32)} (#{as_int32})"
      when "Nil"     then "nil"
      else
        "#<#{t}:0x#{self.object_id.to_s(16)}>"
      end
    end

    # Treat this ICRObject as Int32,UInt64,..
    # Used by primitives.
    {% for t in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64 Bool Char) %}
      def as_{{t.downcase.id}}
        @raw.as({{t.id}}*).value
      end

      def as_{{t.downcase.id}}=(value : {{t.id}})
        @raw.as({{t.id}}*).value = value
      end
    {% end %}

    def as_number : Number
      case @type.cr_type.to_s # TODO avoid the string transformation
      when "Int8"    then self.as_int8
      when "UInt8"   then self.as_uint8
      when "Int16"   then self.as_int16
      when "UInt16"  then self.as_uint16
      when "Int32"   then self.as_int32
      when "UInt32"  then self.as_uint32
      when "Int64"   then self.as_int64
      when "UInt64"  then self.as_uint64
      when "Float32" then self.as_float32
      when "Float64" then self.as_float64
      else                todo "ICRObject to #{@type.cr_type.to_s}"
      end
    end

    def as_string
      addr = @raw.as(UInt64*).value
      ref = Pointer(Byte).new(addr)
      bytesize = (ref + 4).as(Int32*).value
      size = (ref + 8).as(Int32*).value
      # ref.as(String*).value
      String.new((ref + String::HEADER_SIZE), bytesize, size)
    end
  end

  # Creates the corresponding ICRObject from values:

  def self.nil
    ICRObject.new(ICRType.nil)
  end

  def self.bool(value : Bool)
    obj = ICRObject.new(ICRType.bool)
    obj.as_bool = value
    obj
  end

  {% for t in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64) %}
    def self.number(value : {{t.id}})
      obj = ICRObject.new(ICRType.{{t.downcase.id}})
      obj.as_{{t.downcase.id}} = value
      obj
    end
  {% end %}

  def self.number(value)
    todo "#{value.class} to ICRObject"
  end

  def self.char(value : Char)
    obj = ICRObject.new(ICRType.char)
    obj.as_char = value
    obj
  end

  def self.string(value : String)
    ICRObject.new(from_string: value)
  end

  def self.symbol(value : String)
    obj = ICRObject.new(ICRType.new(ICR.program.symbol))
    obj.as_int32 = ICR.get_symbol_value(value)
    obj
  end

  def self.tuple(type : Crystal::Type, elements : Array(ICRObject))
    obj = ICRObject.new(ICRType.new(type))
    elements.each_with_index do |e, i|
      obj[i.to_s] = e
    end
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
    String.build do |io|
      parts = self.split('.')
      parts.each_with_index do |str, part|
        str.each_char_with_index do |c, i|
          i = (part == 0) ? (str.size - 1 - i) : i + 1

          io << c
          if i % 3 == 0 && i != 0 && c != '-'
            io << '_'
          end
        end
        io << '.' unless part == parts.size - 1
      end
    end
  end
end
