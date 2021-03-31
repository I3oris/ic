module ICR
  abstract class ICRObject
    property type : Crystal::Type
    @ivar = {} of String => ICRObject

    def initialize(@type : Crystal::Type)
    end

    def get_type
      @type
    end

    def get_value # !
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

    abstract def result
  end

  class ICRReference < ICRObject
    # def initialize(@type : Crystal::Type)
    # end

    def result
      "#<#{@type.subclasses}:#{self.object_id}>"
    end
  end

  abstract class ICRValue < ICRObject
  end

  class ICRStruct < ICRValue
    # def initialize(@type : Crystal::Type)
    # end
    # Todo instance vars:
    # Foo(@x=5, @y=5)
    def result
      "#{@type.subclasses}()"
    end
  end

  class ICRClass < ICRReference
    def initialize(@type : Crystal::Type, @value : Crystal::Type)
    end

    def result
      @value.inspect
    end

    def get_value
      @value
    end

    def get_type
      # ICR.program.class_type
      @value.metaclass
    end
  end

  class IRCObjectBase < ICRValue
    property value

    def initialize(@type : Crystal::Type, @value : Pointer(Void))
    end

    def initialize(@type : Crystal::Type, value)
      @value = Box.box(value)
    end

    def result
      get_value.inspect
    end

    def get_value
      case @type.to_s
      when "Nil"     then nil
      when "Bool"    then Box(Bool).unbox(@value)
      when "Int32"   then Box(Int32).unbox(@value)
      when "UInt64"  then Box(UInt64).unbox(@value)
      when "Float64" then Box(Float64).unbox(@value)
      when "String"  then Box(String).unbox(@value)
      else                raise_error "Not Implemented type for 'get_value': #{@type}"
      end
    end

    def truthy?
      @type.to_s != "Nil" && !(@type.to_s == "Bool" && Box(Bool).unbox(@value) == false)
    end

    def get_type
      @type # .metaclass
      # case @type
      # when "Nil"     then ICR.program.nil
      # when "Bool"    then ICR.program.bool
      # when "Int32"   then ICR.program.int32
      # when "Float64" then ICR.program.float64
      # when "String"  then ICR.program.string
      # else                raise_error "Not Implemented type for 'get_type': #{@type}"
      # end
    end
  end

  # class ICRPointer < ICRValue
  #   def initialize(@type : Crystal::Type, @value : ICRObject)
  #   end
  # end

  class IRCTuple < ICRValue
    property values

    def initialize(@type : Crystal::Type, @values : Array(ICRObject))
    end

    def result
      "{#{@values.map(&.result).join(", ")}}"
    end

    def get_type
      @type # .metaclass

    end
  end

  def self.nil
    IRCObjectBase.new(ICR.program.nil, nil)
  end

  def self.bool(value : Bool)
    IRCObjectBase.new(ICR.program.bool, value)
  end

  def self.int32(value : Int32)
    IRCObjectBase.new(ICR.program.int32, value)
  end

  def self.uint64(value : UInt64)
    IRCObjectBase.new(ICR.program.uint64, value)
  end

  def self.float64(value : Float64)
    IRCObjectBase.new(ICR.program.float64, value)
  end

  def self.string(value : String)
    IRCObjectBase.new(ICR.program.string, value)
  end

  def self.tuple(values : Array(ICRObject))
    IRCTuple.new(ICR.program.tuple_of(values.map &.get_type), values)
  end

  def self.class_type(value : Crystal::Type)
    ICRClass.new(ICR.program.class_type, value)
  end

  # def self.pointer_of()
end
