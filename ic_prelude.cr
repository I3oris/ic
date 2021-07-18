# This file is read each time icr is launched #

require "primitives"
require "class"

# > You could try to include some other file of the stdlib, but the result will be uncertain.

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

  macro class_getter(*names)
    {% for n in names %}
      def self.{{n.id}}
        @@{{n.id}}
      end
    {% end %}
  end

  macro class_setter(*names)
    {% for n in names %}
      def self.{{n.id}}=(@@{{n.id}})
      end
    {% end %}
  end

  macro class_property(*names)
    class_getter {{*names}}
    class_setter {{*names}}
  end
end

struct Int
  def chr
    unsafe_chr
  end

  def %(other)
    unsafe_mod(other)
  end

  def /(other)
    self.to_f / other.to_f
  end

  def //(other)
    unsafe_div(other)
  end

  def times
    i = 0
    while i < self
      yield i
      i += 1
    end
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

# /!\ this Array is unsafe (array[random_value] = x is possible)
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

  def each
    size.times { |i| yield @buffer[i] }
  end

  def map(& : T -> X) forall X
    new_a = Array(X).new @capacity
    self.each { |x| new_a << yield x }
    new_a
  end

  def to_unsafe
    @buffer
  end
end

class String
  property length, bytesize

  def size
    bytesize
  end

  def self.new(size : Int32)
    str = Pointer(UInt8).malloc(12u64 + size + 1u64)
    str.as(Int32*).value = "".crystal_type_id
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

struct Proc(*T, R)
  def partial(*args : *U) forall U
    {% begin %}
      {% remaining = (T.size - U.size) %}
      ->(
          {% for i in 0...remaining %}
            arg{{i}} : {{T[i + U.size]}},
          {% end %}
        ) {
        call(
          *args,
          {% for i in 0...remaining %}
            arg{{i}},
          {% end %}
        )
      }
    {% end %}
  end
end

def loop
  while true
    yield
  end
end

class String
  def to_s
    self
  end
end

struct Nil
  def to_s
    "nil"
  end
end

lib LibC
  fun printf(UInt8*, ...) : Int32
  fun exit(Int32) : NoReturn
end

def puts(s : String) : Nil
  LibC.printf "%s\n", s
end

def puts(i : Int) : Nil
  LibC.printf "%d\n", i
end

def exit
  LibC.exit 0
end
