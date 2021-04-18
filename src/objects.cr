require "gc"
# GC.disable

module ICR
  # ICRObject are transmitted through the AST Tree, and represents Object created with icr
  #
  # There are constituted of a ICRType and a pointer on the binary representation of the object (`raw`)
  # i.e for a Int32, raw will be a pointer on 4 bytes.
  #
  # For classes, raw will be a pointer on 8 bytes (address), pointing itself on the classes size.
  #
  # The ICRType will give information of how to treat the raw binary.
  #
  # `@type` is always the **runtime* type of the object, and cannot be virtual or an union.
  class ICRObject
    getter type : ICRType
    getter raw : Pointer(Byte)

    def initialize(@type)
      if @type.cr_type.is_a? Crystal::UnionType || @type.cr_type.is_a? Crystal::VirtualType
        bug! "Cannot create a object with a runtime union or virtual type (#{@type.cr_type})"
      end

      case @type.cr_type
      when Crystal::NilType
        @raw = Pointer(Byte).null

      when .reference_like?
        # raw -> ref -> | TYPE_ID (4)
        #               | @ivar 1
        #               | @ivar 2
        #               | ...
        @raw = Pointer(Byte).malloc(8)
        ref = Pointer(Byte).malloc(@type.class_size)
        @raw.as(UInt64*).value = ref.address

        # Write the type id at the first slot:
        id = ICR.get_crystal_type_id(@type.cr_type)
        ref.as(Int32*).value = id
      else
        # raw -> | @ivar 1
        #        | @ivar 2
        #        | ...
        @raw = Pointer(Byte).malloc(@type.size)
      end
    end

    def initialize(@type, from @raw)
      if @type.cr_type.is_a? Crystal::UnionType || @type.cr_type.is_a? Crystal::VirtualType
        bug! "Cannot create a object with a runtime union or virtual type (#{@type.cr_type})"
      end
    end

    # Returns the pointer on the data of this object:
    # raw -> data (for struct)
    # raw -> ref -> data (for classes)
    def data
      if !@type.reference_like?
        @raw
      else
        addr = @raw.as(UInt64*).value
        ref = Pointer(Byte).new(addr)
        ref
      end
    end

    # Read an ivar from this object
    def [](name)
      @type.read_ivar(name, from: self.data)
    end

    # Write an ivar of this object
    def []=(name, value : ICRObject)
      @type.write_ivar(name, value, to: self.data)
    end

    def cast(from : Crystal::Type?, to : Crystal::Type?)
      bug! "Cast from #{@type.cr_type} failed" if from.nil? || to.nil?
      if @type.cr_type.pointer?
        # Pointer cast seems never fail
        return ICRObject.new(ICRType.new(to), from: @raw)
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

    # We construct a union like that: | TYPE_ID of current value
    #                                 | data of current value
    #                                 | ...
    def box_into_union(dst_union : Byte*)
      id = ICR.get_crystal_type_id(@type.cr_type)
      dst_union.as(Int32*).value = id
      (dst_union + 8).copy_from(@raw, @type.size)
    end

    # We admit that union is: | TYPE_ID
    #                         | data...
    def self.unbox_from_union(src_union : Byte*)
      id = src_union.as(Int32*).value
      type = ICRType.new(ICR.get_crystal_type_from_id(id))
      obj = ICRObject.new(type)
      obj.raw.copy_from(src_union + 8, type.size)
      obj
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
        when Crystal::SymbolType then ":#{ICR.get_symbol_from_value(as_int32)}"
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

    # Treat this ICRObject as Int32,UInt64,..
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
        end
      ret || bug! "Trying to read #{t} as a number"
    end

    # def as_string
    #   addr = @raw.as(UInt64*).value
    #   ref = Pointer(Byte).new(addr)
    #   bytesize = (ref + 4).as(Int32*).value
    #   size = (ref + 8).as(Int32*).value
    #   String.new((ref + String::HEADER_SIZE).as(UInt8*), bytesize, size)
    # end
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

  # obj.raw -> ref -> | TYPE_ID (4)
  #                   | @bytesize (4)
  #                   | @length (4)
  #                   | @c    (@bytesize times)
  #                   | ...
  def self.string(value : String)
    obj = ICRObject.new(ICRType.string)
    obj.as_string = value
    # We must set the type id because the crystal_type_id of *true* String
    # isn't the same as crystal_type_id of ICR String
    obj.data.as(Int32*).value = ICR.get_crystal_type_id(ICR.program.string)
    obj
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

  def self.class(type : Crystal::Type)
    type = type.devirtualize

    bug! "Trying to create a class or a module from a non metaclass type (#{type.class})" unless type.responds_to? :instance_type

    obj = ICRObject.new(ICRType.new(type))
    obj.as_int32 = ICR.get_crystal_type_id(type.instance_type, instance: false)
    obj
  end

  def self.uninitialized(type : Crystal::Type)
    ICRObject.new(ICRType.new(type))
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
