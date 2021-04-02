module ICR
  struct Binary
    property size : Int32
    property raw : Pointer(UInt8)

    def initialize(@size : Int32)
      @raw = Pointer(UInt8).malloc(size)
    end

    def free
      @raw.free
    end
  end

  abstract class ICRObject
    property type : Crystal::Type
    @ivar = {} of String => ICRObject
    @generics = [] of Crystal::Type

    def initialize(@type : Crystal::Type)
    end

    abstract def to_binary

    def self.from_binary(b : Binary)
      raise_error "TODO #{self.class}.from_binary"
    end

    def get_ivar(name : String) : ICRObject
      @ivar[name]? || raise_error "BUG: #{result} doesn't have a ivar: #{name}"
    end

    def set_ivar(name : String, value : ICRObject) : ICRObject
      @ivar[name] = value
    end

    # TODO Null Pointer falsly
    def truthy?
      true
    end

    # TODO replace by inspect call
    abstract def result
  end

  class ICRReference < ICRObject
    def result
      "#<#{@type}:#{self.object_id}>"
    end

    def to_binary
      raise "TODO: ICRReference.to_binary"
    end
    # def self.from_binary
    # end
  end

  # TODO Remove this class because it entierly defined in sdt lib
  class ICRString < ICRReference
    property value

    def initialize(@value : String)
      @type = ICR.program.string
    end

    def result
      @value.inspect
    end
  end

  def self.string(value)
    ICRString.new(value)
  end

  abstract class ICRValue < ICRObject
  end

  class ICRStruct < ICRValue
    # def initialize(@type : Crystal::Type)
    # end

    # TODO instance vars:
    # Foo(@x=5, @y=5)
    def result
      "#{@type}()"
    end

    def to_binary
      raise_error "TODO ICRReference.to_binary"
    end
  end

  class ICRClass < ICRValue
    property target

    def initialize(@target : Crystal::Type)
      @type = ICR.program.class_type
    end

    def result
      @target.inspect
    end

    def to_binary
      raise_error "TODO ICRClass.to_binary"
    end
    # /!\
    # def type
    #   @target.metaclass
    # end
  end

  def self.class_type(value)
    ICRClass.new(value)
  end

  # @[Deprecated]
  # class IRCObjectBase < ICRValue
  #   property value

  #   def initialize(@type : Crystal::Type, @value : Pointer(Void))
  #   end

  #   def initialize(@type : Crystal::Type, value)
  #     @value = Box.box(value)
  #   end

  #   def result
  #     get_value.inspect
  #   end

  #   def get_value
  #     case @type.to_s
  #     when "Nil"     then nil
  #     when "Bool"    then Box(Bool).unbox(@value)
  #     when "Int32"   then Box(Int32).unbox(@value)
  #     when "UInt64"  then Box(UInt64).unbox(@value)
  #     when "Float64" then Box(Float64).unbox(@value)
  #     when "String"  then Box(String).unbox(@value)
  #     else                raise_error "Not Implemented type for 'get_value': #{@type}"
  #     end
  #   end

  #   def truthy?
  #     @type.to_s != "Nil" && !(@type.to_s == "Bool" && Box(Bool).unbox(@value) == false)
  #   end

  #   def get_type
  #     @type # .metaclass
  #     # case @type
  #     # when "Nil"     then ICR.program.nil
  #     # when "Bool"    then ICR.program.bool
  #     # when "Int32"   then ICR.program.int32
  #     # when "Float64" then ICR.program.float64
  #     # when "String"  then ICR.program.string
  #     # else                raise_error "Not Implemented type for 'get_type': #{@type}"
  #     # end
  #   end
  # end

  # class ICRPointer < ICRValue
  #   def initialize(@type : Crystal::Type, @value : ICRObject)
  #   end
  # end

  class IRCTuple < ICRValue
    property values

    def initialize(@values : Array(ICRObject))
      @type = ICR.program.tuple_of(values.map &.type)
    end

    def result
      "{#{@values.map(&.result).join(", ")}}"
    end

    def to_binary
      raise_error "TODO ICRTuple.to_binary"
    end
  end

  def self.tuple(values)
    IRCTuple.new(values)
  end

  class ICRNil < ICRValue
    def initialize
      @type = ICR.program.nil
    end

    def to_binary
      Binary.new 0
    end

    def result
      "nil"
    end
  end

  def self.nil
    # IRCObjectBase.new(ICR.program.nil, nil)
    ICRNil.new
  end

  abstract class ICRNumber < ICRValue
    # @type = ICR.program.nil # This type should be ever override!
    # abstract def initialize(value)
    abstract def value
  end

  abstract class ICRInt < ICRNumber
  end

  abstract class ICRFloat < ICRNumber
  end

  {% for type, info in {
                         "Int32"   => %w(Int i32),
                         "UInt64"  => %w(Int u64),
                         "Float64" => %w(Float f64),
                       } %}
    {%
      parent = info[0]
      sufix = info[1]
    %}
    class ICR{{type.id}} < ICR{{parent.id}}
      property value : {{type.id}}

      def initialize(value : Number)
        @value = value.to_{{sufix.id}}
        @type = ICR.program.{{type.downcase.id}}
      end

      def to_binary
        b = Binary.new(sizeof({{type.id}}))
        b.raw.as({{type.id}}*).value = @value
        b
      end

      def self.from_binary(b : Binary)
        self.new(b.raw.as({{type.id}}*).value)
      end

      def result
        value.inspect
      end

      {% unless type == "Bool" %}
        def primitive_op(op_name,other : ICRNumber)
          case op_name
          {% for op in %w(+ * -) %}
            when {{op}} then ICR{{type.id}}.new(@value {{op.id}} other.value)
          {% end %}

          {% for op in %w(== != <= >= < >) %}
            when {{op}} then ICRBool.new(@value {{op.id}} other.value)
          {% end %}
          else
            raise_error "BUG: unsuported primitive #{op_name} for #{self.class}"
          end
        end
      {% end %}
    end

    def self.{{type.downcase.id}}(value)
      ICR{{type.id}}.new(value)
    end
  {% end %}

  class ICRBool < ICRValue
    property value

    def initialize(@value : Bool)
      @type = ICR.program.bool
    end

    def to_binary
      b = Binary.new(sizeof(Bool))
      b.raw.as(Bool*).value = @value
      b
    end

    def self.from_binary(b : Binary)
      self.new(b.raw.as(Bool*).value)
    end

    def truthy?
      @value == true
    end

    def result
      value.inspect
    end
  end

  def self.bool(value)
    ICRBool.new(value)
  end

  class ICRPointer < ICRValue
    @address = Pointer(UInt8).null

    def initialize(_T : Crystal::Type, value : ICRObject)
      @type = ICR.program.pointer_of(_T)
      @generics = [_T]
      if value.responds_to?(:to_binary)
        b = value.to_binary
        @address = b.raw
      else
        raise_error "BUG: unsupported pointer of #{value.class}"
      end
    end

    def free
      @address.free
    end

    def truthy?
      true # TODO
    end

    def to_binary
      raise_error "TODO ICRPointer.to_binary"
    end

    def result
      "#<Pointer(#{@generics.join("'")}) @address=#{@address}>"
    end
  end

  def self.pointer_of(_T,value)
    ICRPointer.new(_T,value)
  end

  # def self.int32(value : Int32)
  #   IRCObjectBase.new(ICR.program.int32, value)
  # end

  # def self.uint64(value : UInt64)
  #   IRCObjectBase.new(ICR.program.uint64, value)
  # end

  # def self.float64(value : Float64)
  #   IRCObjectBase.new(ICR.program.float64, value)
  # end

  # def self.pointer_of()
end
