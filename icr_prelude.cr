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
  def [](i : Int32)
    i64 = 0i64 + i
    (self + i64).value
  end

  def []=(i : Int32, value : T)
    i64 = 0i64 + i
    (self + i64).value = value
  end

  def +(i : Int32)
    i64 = 0i64 + i
    self + i64
  end

  def copy_from(source : Pointer(T), count : Int32)
    while (count -= 1) >= 0
      self[count] = source[count]
    end
    self
  end
end

class Array(T)
  property size

  def self.unsafe_build(size)
    a = Array(T).new 20u64
    a.size = size
    a
  end

  def initialize(@capacity : UInt64 = 20u64)
    @size = 0
    @buffer = Pointer(T).malloc @capacity
  end

  def [](i : Int32)
    @buffer[i]
  end

  def []=(i : Int32, value : T)
    @buffer[i] = value
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

class String
  property length, bytesize

  def size
    length
  end

  def self.new(size : Int32)
    str = Pointer(UInt8).malloc(12u64 + size + 1u64)
    str.as(String).length = size
    str.as(String).bytesize = size
    str.as(String)
  end

  def +(other : String)
    str = String.new(@bytesize + other.bytesize)
    str.to_unsafe.copy_from(self.to_unsafe, @bytesize)
    (str.to_unsafe + @bytesize).copy_from(other.to_unsafe, other.bytesize)
    str
  end

  def to_unsafe
    pointerof(@c)
  end
end

struct Tuple(*T)
  def [](index : Int32)
    index += size if index < 0
    {% for i in 0...T.size %}
      return self[{{i}}] if {{i}} == index
    {% end %}
    yield
  end
end
