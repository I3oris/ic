{% for type in %w(Int32 UInt64) %}
  struct {{type.id}}
    {% for op in %w(+ - * == != <= >= < >) %}
      @[Primitive(:binary)]
      def {{op.id}}(other : {{type.id}}) : self
      end
    {% end %}
  end
{% end %}

class Object
  @[Primitive(:class)]
  def class
  end

  # :nodoc:
  @[Primitive(:object_crystal_type_id)]
  def crystal_type_id : Int32
  end

  macro getter(*names)
    {% for n in names %}
      def {{n.id}}
        @{{n.id}}
      end
    {% end %}
  end

  macro setter(*names)
    {% for n in names %}
      def {{n.id}}=(@{{n.id}})
      end
    {% end %}
  end

  macro property(*names)
    getter {{*names}}
    setter {{*names}}
  end
end

class Reference
  @[Primitive(:object_id)]
  def object_id : UInt64
  end
end

class Class
  @[Primitive(:class_crystal_instance_type_id)]
  def crystal_instance_type_id : Int32
  end
end

struct Pointer(T)

  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64)
  end

  @[Primitive(:pointer_new)]
  def self.new(address : UInt64)
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  @[Primitive(:pointer_set)]
  def value=(value : T)
  end

  @[Primitive(:pointer_address)]
  def address : UInt64
  end

  @[Primitive(:pointer_realloc)]
  def realloc(size : UInt64) : self
  end

  @[Primitive(:pointer_add)]
  # def +(offset : Int64) : self
  def +(offset : Int32) : self
  end

  @[Primitive(:pointer_diff)]
  def -(other : self) : Int64
  end
end

struct Pointer(T)
  def [](i : Int32)
    (self+i).value
  end

  def []=(i : Int32, value : T)
    (self+i).value = value
  end
end

class Array(T)
  property size

  def self.unsafe_build(size)
    a = Array(T).new 20u64
    a.size = size
    a
  end

  def initialize(@capacity : UInt64)
    @size = 0
    @buffer = Pointer(T).malloc @capacity
  end

  def [](i : Int32)
    if i < @size
      @buffer[i]
    end
  end

  def []=(i : Int32, value : T)
    if i < @size
      @buffer[i] = value
    end
  end

  def <<(value)
    @buffer[@size] = value
    @size += 1
    self
  end

  def to_unsafe
    @buffer
  end
end