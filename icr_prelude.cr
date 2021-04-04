require "../../../../../usr/share/crystal/src/primitives"

# Some minimal tests to replace crystal API lib:

class Object
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

struct Pointer(T)
  @[Primitive(:pointer_add)]
  # def +(offset : Int64) : self
  def +(offset : Int32) : self
  end
end

struct Pointer(T)
  def [](i : Int32)
    (self + i).value
  end

  def []=(i : Int32, value : T)
    (self + i).value = value
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
