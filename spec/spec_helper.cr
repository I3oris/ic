require "spec"
require "../src/ic"

module IC
  def self.running_spec?
    true
  end

  def self.run_spec(code)
    VarStack.reset
    IC.parse(code).run.result
  end
end

IC.parse(<<-'CODE').run
  class SpecClass
    property x
    property y
    property name

    class_property c_foo, c_bar
    @@c_foo : Symbol?
    @@c_bar = "bar"

    def initialize(@x = 0, @y = 0, @name = "unnamed")
    end
  end

  class SpecSubClass1 < SpecClass
    @bar = "foo"
    property bar

    @@c_bar = "sub_bar"
  end

  class SpecSubClass2 < SpecClass
    @baz = :baz
    property baz

    @@c_foo : Symbol?
  end

  struct SpecStruct
    property x
    property y
    property name

    def initialize(@x = 0, @y = 0, @name = "unnamed")
    end
  end

  class SpecUnionIvars
    @union_values : Int32|SpecStruct|Nil = nil
    @union_reference_like : SpecClass|String|Nil = nil
    @union_mixed : SpecStruct|SpecClass|Nil = nil

    property union_values, union_reference_like, union_mixed

    def all
      {@union_values, @union_reference_like, @union_mixed}
    end
  end

  class SpecGenericClass(X,Y,Z)
    def self.type_vars
      {X,Y,Z}
    end
  end

  enum SpecEnum
    A
    B
    C
  end

  def yield_func1(*args)
    yield args
  end

  def yield_func2(a)
    b = a
    yield_func1(31) do |a|
      yield a[0] + b
    end
  end

  def yield_func3(a,b)
    (yield a+b)+(yield(yield a*2))
  end

  def yield_func4(a, b)
    x = yield a + b, b
    y = yield x, a
    x + y
  end

  def yield_func5(x)
    while x < yield 0
      x += yield x
      break if x > 10000
    end
    yield (-1 + x)
  end

  def times_func(n)
    i = 0
    while i < n
      yield i
      i += 1
    end
  end

  def enum_func(x : SpecEnum, *args : SpecEnum, **options : SpecEnum)
    {x, args, options}
  end

  def set_global(value)
    $~ = value
  end

  CODE
