module ICR
  class ICRObject
    property type

    def initialize(@type : String)
    end

    def get_type
      raise_error "Not Implemented type for 'get_type': #{@type}"
    end

    def get_value
    end
  end

  class IRCObjectBase < ICRObject
    property value

    def initialize(@type : String, @value : Pointer(Void))
    end

    def initialize(@type : String, value)
      @value = Box.box(value)
    end

    def get_value
      case @type
      when "Nil"     then nil
      when "Bool"    then Box(Bool).unbox(@value)
      when "Int32"   then Box(Int32).unbox(@value)
      when "Float64" then Box(Float64).unbox(@value)
      when "String"  then Box(String).unbox(@value)
      else                raise_error "Not Implemented type for 'get_value': #{@type}"
      end
    end

    def get_type
      case @type
      when "Nil"     then ICR.program.nil
      when "Bool"    then ICR.program.bool
      when "Int32"   then ICR.program.int32
      when "Float64" then ICR.program.float64
      when "String"  then ICR.program.string
      else                raise_error "Not Implemented type for 'get_type': #{@type}"
      end
    end
  end

  class IRCTuple < ICRObject
    property values

    def initialize(@type : String, @values : Array(ICRObject))
    end

    def get_type
      ICR.program.tuple_of(@values.map &.get_type.metaclass)
    end
  end

  def self.nil
    IRCObjectBase.new("Nil", nil)
  end

  def self.bool(value : Bool)
    IRCObjectBase.new("Bool", value)
  end

  def self.int32(value : Int32)
    IRCObjectBase.new("Int32", value)
  end

  def self.float64(value : Float64)
    IRCObjectBase.new("Float64", value)
  end

  def self.string(value : String)
    IRCObjectBase.new("String", value)
  end

  def self.tuple(values : Array(ICRObject))
    IRCTuple.new("Tuple", values)
  end
end
