require "./spec_helper"

describe IC do
  describe Crystal::Type do
    it "describe Nil" do
      IC.program.nil.reference?.should eq false
      IC.program.nil.ic_size.should eq 0
      IC.program.nil.copy_size.should eq 8
    end

    it "describe Int32" do
      IC.program.int32.reference?.should eq false
      IC.program.int32.ic_size.should eq 4
      IC.program.int32.copy_size.should eq 4
    end

    it "describe String" do
      IC.program.string.reference?.should eq true
      IC.program.string.ic_size.should eq 8
      IC.program.string.copy_size.should eq 8
      IC.program.string.ic_class_size.should eq 16
    end
  end

  describe :scenarios do
    it "runs scenario 1" do
      IC.run_spec("1+1").should eq "2"
    end

    it "runs scenario 2" do
      IC.run_spec(<<-'CODE').should eq %({42, 31})
        class Point
          property x, y
          def initialize(@x = 42, @y = 31)
          end
        end

        p = Point.new

        class Point
          def xy
            {@x, @y}
          end
        end

        p.xy
        CODE
    end

    it "runs scenario 3" do
      IC.run_spec(<<-'CODE').should eq %({nil, 42, nil, nil, nil, 31, 77, "hello"})
        class Foo
          property x, y, z, t
          @x : Nil
          def initialize(@y = 42,
                         @z : Int32 | Nil = nil,
                         @t : String | Nil = nil)
          end
        end
        foo = Foo.new
        x, y, z, t = foo.x, foo.y, foo.z, foo.t
        foo.x, foo.y, foo.z, foo.t = nil, 31, 77, "hello"

        {x ,y, z, t, foo.x, foo.y, foo.z, foo.t}
        CODE
    end

    it "runs scenario 4" do
      IC.run_spec(<<-'CODE').should eq %({Int32, String, (Int32 | String)})
        x = 42
        t1 = typeof(x)
        x = "42"
        t2 = typeof(x)
        y = 42 || "42"
        t3 = typeof(y)
        {t1, t2, t3}
        CODE
    end

    it "runs scenario 5" do
      IC.run_spec(<<-'CODE').should eq %(177_189_926)

        yield_func4(42, 7) do |a, b|
          if a < b
            yield_func3(a, b - 1) { |x| x }
          else
            yield_func3(b, yield_func4(1, 7) { |a| a + 1 }) do |x|
              x + a - b + (yield_func5(a) do |x|
                x2 = x//100
                if x2 == 0
                  a*1000
                elsif x2 > 1000
                  next x*7
                else
                  x*7
                end
              end)
            end
          end
        end
        CODE
    end

    it "runs scenario 6" do
      IC.run_spec(<<-'CODE').should eq %(617_918)
        x=42

        p1 = ->(a : Int32, b : Int32){a+b}
        p2 = ->(a : Int32, b : Int32, c : Int32){a+p1.call(b,c)}
        p3 = ->(a : Int32, b : Int32){ p2.call(b, p2.call(a,2*a,b), a-10 )}
        p4 = ->(p1_ : Proc(Int32,Int32,Int32,Int32), p2_ : Proc(Proc(Int32)), arg : Int32) do
          ->(y : Int32) do
            p3.call( p1_.call(arg+x,5,arg-4), p2_.call.call)*y
          end
        end

        p4.call(->(c : Int32, b : Int32, a : Int32) do
          p4.call(p2, ->{p1.partial(42, c)}, 7+c ).call 31+a+b
        end,->{p3.partial(1,2)},-1).call 7
        CODE
    end
  end

  describe :string do
    it "creates empty string" do
      IC.run_spec(%("")).should eq %("")
    end

    it "adds string" do
      IC.run_spec(%("Hello "+"World"+"!")).should eq %("Hello World!")
    end
  end

  describe :array do
    it "fetch" do
      IC.run_spec(%([0,42,5][1])).should eq %(42)
    end

    it "supports many types'" do
      IC.run_spec(%([0,:foo,"bar"][1])).should eq %(:foo)
    end
  end

  describe :primitives do
    it "allocates" do
      IC.run_spec(%(SpecClass.new)).should match /#<SpecClass:0x.*>/
      IC.run_spec(%(SpecStruct.new)).should match /#<SpecStruct>/
    end

    it "does binary op" do
      IC.run_spec(%(1+1)).should eq %(2)
      IC.run_spec(%(0.14+3)).should eq %(3.14)
      IC.run_spec(%(1-1)).should eq %(0)
      IC.run_spec(%(0.14-3)).should eq %(-2.86)
      IC.run_spec(%(3*4)).should eq %(12)
      IC.run_spec(%(3.14*4)).should eq %(12.56)
      # IC.run_spec(%(3/4)).should eq %(0.75)
      IC.run_spec(%(3.14/4)).should eq %(0.785)
      IC.run_spec(%(1 < 2)).should eq %(true)
      IC.run_spec(%(1 > 2)).should eq %(false)
      IC.run_spec(%(1 != 2)).should eq %(true)
      IC.run_spec(%(1 == 2)).should eq %(false)
      IC.run_spec(%(1 <= 2)).should eq %(true)
      IC.run_spec(%(1 >= 2)).should eq %(false)
      IC.run_spec(%('a' < 'b')).should eq %(true)
      IC.run_spec(%('a' > 'b')).should eq %(false)
      IC.run_spec(%('a' != 'b')).should eq %(true)
      IC.run_spec(%('a' == 'b')).should eq %(false)
      IC.run_spec(%('a' <= 'b')).should eq %(true)
      IC.run_spec(%('a' >= 'b')).should eq %(false)
      IC.run_spec(%(0b0010_1010 | 0b1100_0010 == 0b1110_1010)).should eq %(true)
      IC.run_spec(%(0b0010_1010 & 0b1100_0010 == 0b0000_0010)).should eq %(true)
      IC.run_spec(%(0b0010_1010 ^ 0b1100_0010 == 0b1110_1000)).should eq %(true)
    end

    # Need to include "int" to access MAX and MIN, but in practice spec works
    pending "does unsafe binary op" do
      {% for int in %w(UInt8 Int8 UInt16 Int16 UInt32 Int32 UInt64 Int64) %}
        IC.run_spec(%({{int.id}}::MAX &+ 1 == {{int.id}}::MIN)).should eq %(true)
        IC.run_spec(%({{int.id}}::MIN &- 1 == {{int.id}}::MAX)).should eq %(true)
      {% end %}
      IC.run_spec(%(0b1100_0010u8.unsafe_shr(3) == 0b0001_1000u8)).should eq %(true)
      IC.run_spec(%(0b1100_0010u8.unsafe_shl(3) == 0b0001_0000u8)).should eq %(true)
      IC.run_spec(%(1.unsafe_div(2))).should eq %(0)
      IC.run_spec(%(1.unsafe_mod(2))).should eq %(1)
      IC.run_spec(%(42.unsafe_div(5))).should eq %(8)
      IC.run_spec(%(42.unsafe_mod(5))).should eq %(2)
      IC.run_spec(%(42.unsafe_mod(-5))).should eq %(2)
      IC.run_spec(%(-42.unsafe_mod(5))).should eq %(-2)
      IC.run_spec(%(-42.unsafe_mod(-5))).should eq %(-2)
    end

    it "convert" do
      IC.run_spec(%(42.unsafe_chr)).should eq %('*')
      IC.run_spec(%(42u8.unsafe_chr)).should eq %('*')
      IC.run_spec(%(42i64.unsafe_chr)).should eq %('*')
      IC.run_spec(%('*'.ord)).should eq %(42)

      IC.run_spec(%(3.14_f32.to_f)).should eq %(3.140_000_104_904_175) # Normal imprecision with float
      IC.run_spec(%(3.14    .to_i)).should eq %(3)
      IC.run_spec(%(3.14    .to_u)).should eq %(3_u32)
      IC.run_spec(%(1       .to_u8)).should eq %(1_u8)
      IC.run_spec(%(42      .to_u16)).should eq %(42_u16)
      IC.run_spec(%(3.14    .to_u32)).should eq %(3_u32)
      IC.run_spec(%(7_i64   .to_u64)).should eq %(0x7)
      IC.run_spec(%(-1      .to_i8)).should eq %(-1_i8)
      IC.run_spec(%(42_i8   .to_i16)).should eq %(42_i16)
      IC.run_spec(%(-3.14   .to_i32)).should eq %(-3)
      IC.run_spec(%(7_u16   .to_i64)).should eq %(7_i64)
      IC.run_spec(%(42_u64  .to_f32)).should eq %(42.0_f32)
      IC.run_spec(%(-3.14   .to_f64)).should eq %(-3.14)
    end

    # Need to include "int" to access MAX and MIN,
    pending "convert (unchecked)" do
      IC.run_spec(%(-1i8.to_u8! == UInt8::MAX)).should eq %(true)
      IC.run_spec(%(-1i16.to_u16! == UInt16::MAX)).should eq %(true)
      IC.run_spec(%(-1i32.to_u32! == UInt32::MAX)).should eq %(true)
      IC.run_spec(%(-1i64.to_u64! == UInt64::MAX)).should eq %(true)
      IC.run_spec(%(3.14_f32.to_f64!)).should eq %(3.140_000_104_904_175)
      IC.run_spec(%(Float64::MAX.to_f32!)).should eq %(Infinity)
    end

    it "does pointer malloc" do
      IC.run_spec(<<-'CODE').should eq %({0, 0})
        p = Pointer(Int32).malloc 2
        { p[0], p[1] }
        CODE
    end

    it "realloc pointer" do
      IC.run_spec(<<-'CODE').should eq %({42, 31, -1, 7})
        p = Pointer(Int32).malloc 2
        p[0], p[1] = 42, 31
        p = p.realloc 4
        p[2], p[3] = -1, 7
        { p[0], p[1], p[2], p[3] }
        CODE
    end

    it "does pointer new && pointer address" do
      IC.run_spec(%(Pointer(Int32).new(0x42).address)).should eq %(0x42)
    end

    it "sets && gets pointers" do
      IC.run_spec(<<-'CODE').should eq %({42, 31})
        p = Pointer(Int32).malloc 2
        (p+1).value = 31
        p.value = 42
        { p.value, (p+1).value }
        CODE
    end

    it "adds pointers" do
      IC.run_spec(<<-'CODE').should eq %(0x9)
        p = Pointer(Int32).new(0x1)
        (p+2).address
        CODE
    end

    it "subtracts pointers" do
      IC.run_spec(<<-'CODE').should eq %({-4_i64, 4_i64, -42_i64, 42_i64})
        p1 = Pointer(Int32).new(16)
        p2 = Pointer(Int32).new(32)
        p3 = Pointer(SpecStruct).malloc(1)
        p4 = Pointer(SpecStruct).new (p3+42).address
        {
          p1-p2,
          p2-p1,
          p3-p4,
          p4-p3,
        }
        CODE
    end

    it "index tuple" do
      IC.run_spec(<<-'CODE').should eq %({0, 'x', :foo, "bar"})
        t = {0,'x',:foo,"bar"}
        {t[0],t[1],t[2],t[3]}
        CODE
    end

    it "gives the good object_id" do
      IC.run_spec(<<-'CODE').should eq %(true)
        foo = SpecClass.new 0,0
        pointerof(foo).as(UInt64*).value == foo.object_id
        CODE
    end

    it "gives the good crystal_type_id" do
      IC.run_spec(<<-'CODE').should eq %(true)
        foo = SpecClass.new 0,0
        Pointer(Int32).new(foo.object_id).value == foo.crystal_type_id
        CODE
    end

    it "gives the good class_crystal_instance_type_id" do
      IC.run_spec(<<-'CODE').should eq %(true)
        x = 42 || "foo"
        (x.class.crystal_instance_type_id == Int32.crystal_instance_type_id == x.crystal_type_id)
        CODE
    end

    it "gives class" do
      IC.run_spec(<<-'CODE').should eq %({Int32, Char, Symbol, String, SpecClass, SpecSubClass1, SpecStruct, Int32})
        x = 42 || "foo"
        {
          0.class,
          'x'.class,
          :foo.class,
          "bar".class,
          SpecClass.new.class,
          SpecSubClass1.new.class,
          SpecStruct.new.class,
          x.class
        }
        CODE
    end

    it "convert symbol to string" do
      IC.run_spec(%(:foo.to_s)).should eq %("foo")
      IC.run_spec(%(:"$/*♥".to_s)).should eq %("$/*♥")
      IC.run_spec(%(:+.to_s)).should eq %("+")
    end

    it "gets enum value" do
      IC.run_spec(%(SpecEnum::A.value)).should eq %(0)
      IC.run_spec(%(SpecEnum::B.value)).should eq %(1)
      IC.run_spec(%(SpecEnum::C.value)).should eq %(2)
    end

    it "creates new enum" do
      IC.run_spec(%(SpecEnum.new 0)).should eq %(A)
      IC.run_spec(%(SpecEnum.new 1)).should eq %(B)
      IC.run_spec(%(SpecEnum.new 2)).should eq %(C)
      IC.run_spec(%(SpecEnum.new 42)).should eq %(SpecEnum:42)
    end

    it "call proc" do
      IC.run_spec(%(->(x : Int32){x+1}.call 1)).should eq %(2)
    end
  end

  describe :classes do
    it "supports instance vars" do
      IC.run_spec(<<-'CODE').should eq %({42, 31, "hello"})
        foo = SpecClass.new 42, 31
        foo.name = "hello"
        { foo.x, foo.y, foo.name }
        CODE
    end

    # got SpecClass+ instead of SpecSubClass1
    pending "preserve class on cast (unless Pointers)" do
      IC.run_spec(<<-'CODE').should eq %({SpecSubClass1, Int32, Pointer(UInt64)})
        b = SpecSubClass1.new
        x = 42
        p = Pointer(Int32).new 42
        {
          b.as(SpecClass).class,
          x.as(Int32|String).class,
          p.as(UInt64*).class,
        }
        CODE
    end
  end

  describe :generics do
    IC.run_spec(%(SpecGenericClass(Int32, 42, 31u8).type_vars)).should eq %({Int32, 42, 31_u8})
  end

  describe :pointerof do
    it "takes address of a local var" do
      IC.run_spec(<<-'CODE').should eq %({42, 31})
        a = 7
        p = pointerof(a)
        a = 42
        r1 = p.value # 42
        p.value = 31
        r2 = a # 31
        {r1, r2}
        CODE
    end
  end

  describe :const do
    it "declares a CONST" do
      IC.run_spec(%(FOO1 = "foo")).should eq %("foo")
      IC.run_spec(%(FOO1)).should eq %("foo")
    end

    it "declares a scoped CONST" do
      IC.run_spec(<<-'CODE').should eq %({"foo", "bar", :baz})
        Const1::Const2::CONST3 = "foo"
        module Const4
          class Const5
            CONST6 = "bar"
            CONST7 = :baz
          end
        end
        {
          Const1::Const2::CONST3,
          Const4::Const5::CONST6,
          Const4::Const5::CONST7,
        }
        CODE
    end

    # got "local" instead of "out"
    pending "preserves a local scope on initializers" do
      IC.run_spec(<<-'CODE').should eq %("out")
        x = "out"
        FOO2=(x="local")
        x
        CODE
    end

    it "executes semantics on initializers" do
      IC.run_spec(<<-'CODE').should eq %("foo")
        FOO3=({{"foo"}})
        CODE
    end

    it "preserves initialization order" do
      IC.run_spec(<<-'CODE').should eq %({"1, begin A, B, end A, 2, 3", 2, 2, 1})
        class Trace
          @@trace = ""
          class_property trace
        end

        Trace.trace = "1, "
        A=(Trace.trace += "begin A, "; a=B+1; Trace.trace += "end A, "; a)
        Trace.trace += "2, "
        B=(Trace.trace += "B, "; 1)
        Trace.trace += "3"
        {Trace.trace, A, A, B}
        CODE
    end
  end

  describe :class_vars do
    it "initializes cvars" do
      IC.run_spec(<<-'CODE').should eq %({nil, "bar", nil, "sub_bar", nil, "bar"})
        {
          SpecClass.c_foo,
          SpecClass.c_bar,
          SpecSubClass1.c_foo,
          SpecSubClass1.c_bar,
          SpecSubClass2.c_foo,
          SpecSubClass2.c_bar,
        }
        CODE

      IC.run_spec(<<-'CODE').should eq %({:a, "bar", nil, "b", :c, :d})
        SpecClass.c_foo = :a
        SpecSubClass1.c_bar = "b"
        SpecSubClass2.c_foo = :c
        SpecSubClass2.c_bar = :d
        {
          SpecClass.c_foo,
          SpecClass.c_bar,
          SpecSubClass1.c_foo,
          SpecSubClass1.c_bar,
          SpecSubClass2.c_foo,
          SpecSubClass2.c_bar,
        }
        CODE
    end
  end

  describe :globals do
    # undefined method 'not_nil!' for Nil
    pending "use $~" do
      IC.run_spec(<<-'CODE').should eq %("foo")
        set_global("foo")
        $~
       CODE
    end
  end

  describe :union do
    # got SpecClass+ instead of SpecClass
    pending "gives a good union virtual type" do
      IC.run_spec(<<-'CODE').should eq %({SpecClass, true, false})
        foobar = SpecSubClass1|SpecSubClass2
        {foobar, foobar.is_a?(SpecClass.class), foobar == SpecClass}
        CODE
    end

    it "support union ivars (1)" do
      IC.run_spec(<<-'CODE').should match /\{42, #<SpecClass:0x.*>, #<SpecStruct>\}/
        foo = SpecUnionIvars.new
        foo.union_values = 42
        foo.union_reference_like = SpecClass.new
        foo.union_mixed = SpecStruct.new
        foo.all
        CODE
    end

    it "support union ivars (2)" do
      IC.run_spec(<<-'CODE').should match /\{#<SpecStruct>, "foo", #<SpecClass:0x.*>\}/
        foo = SpecUnionIvars.new
        foo.union_values = SpecStruct.new
        foo.union_reference_like = "foo"
        foo.union_mixed = SpecClass.new
        foo.all
        CODE
    end
  end

  describe :ivars_initializers do
    it "initializes ivars" do
      IC.run_spec(<<-'CODE').should eq %({:foo, nil, :foo, nil, 7, :foo, nil, nil})
        a = SpecIvarsInitializer.new
        b = SpecSubIvarsInitializer.new
        c = SpecIvarsInitializerGeneric(Symbol, Float64).new
        {a.foo, a.bar, b.foo, b.bar, b.baz, c.foo, c.bar, c.t}
        CODE
    end

    it "changes value of initialized ivars" do
      IC.run_spec(<<-'CODE').should eq %({:FOO, "bar", :FOO2, "BAR", :FOO, "bar", :foo, nil, {:T, 3.14}})
        a = SpecIvarsInitializer.new
        b = SpecSubIvarsInitializer.new
        c = SpecIvarsInitializerGeneric(Symbol, Float64).new
        a.foo = :FOO
        a.bar = "bar"
        b.foo = :FOO2
        b.bar = "BAR"
        b.baz = a
        c.t = {:T, 3.14}
        baz = b.baz.as(SpecIvarsInitializer)
        {a.foo, a.bar, b.foo, b.bar, baz.foo, baz.bar, c.foo, c.bar, c.t}
        CODE
    end
  end

  describe :enums do
    it "declares a basic enum" do
      IC.run_spec(<<-'CODE').should eq %({0, 1, 2, 5, 3})
        enum Enum1
          A
          B
          C
          D = B+2*C
          E = D*C - (C|D)
        end
        {Enum1::A.value, Enum1::B.value, Enum1::C.value, Enum1::D.value, Enum1::E.value}
        CODE

      IC.run_spec(%(Enum1::A.class)).should eq %(Enum1)
    end

    it "declares a flags enum" do
      IC.run_spec(<<-'CODE').should eq %({1, 2, 4, 8, 16})
        @[Flags]
        enum Enum2
          A
          B
          C
          D
          E
        end
        {Enum2::A.value, Enum2::B.value, Enum2::C.value, Enum2::D.value, Enum2::E.value}
        CODE
    end

    it "declares a typed enum" do
      IC.run_spec(<<-'CODE').should eq %({4_u8, 5_u8, 6_u8})
        enum Enum3 : UInt8
          A = 4
          B
          C
        end
        {Enum3::A.value, Enum3::B.value, Enum3::C.value}
        CODE
    end

    it "convert symbol to enum" do
      IC.run_spec(<<-'CODE').should eq %({A, {B, C}, {foo: A, bar: B}})
        enum_func :a, :b, :c, foo: :a, bar: :b
        CODE
    end
  end

  describe :yield do
    it "yields" do
      IC.run_spec(<<-'CODE').should eq %(10)
        yield_func1(1,2,3,4) do |a,b,c,d|
          yield_func1(a+b,c,d) do |a,b,c|
            yield_func1(a+b,c) do |a,b|
              yield_func1(a+b) do |a|
                a[0]
              end
            end
          end
        end
        CODE
      IC.run_spec(<<-'CODE').should eq %(41)
        a = 42
        yield_func1(0) do |a|
          yield_func2(a[0] + 10) { |a| a }
        end
        CODE
    end

    it "breaks" do
      IC.run_spec(<<-'CODE').should eq %(3)
        i = 0
        while i < 10
          break if i == 3
          i += 1
        end
        i
        CODE

      IC.run_spec(<<-'CODE').should eq %({42, 31})
        yield_func1 do
          break 42, 31
        end
        CODE

      IC.run_spec(<<-'CODE').should eq %(7)
        yield_func1 do
          yield_func1 do
            break 42, 31
          end
          7
        end
        CODE
    end

    it "next" do
      IC.run_spec(<<-'CODE').should eq %(9)
        i = 0
        x = 0
        while i<6
          i += 1
          next if i % 2 == 0
          x += i
        end
        x
        CODE

      IC.run_spec(<<-'CODE').should eq %(9)
        x = 0
        times_func(6) do |i|
          next if i % 2 == 0
          x += i
        end
        x
        CODE
    end

    it "cover the good scope" do
      IC.run_spec(<<-'CODE').should eq %({42, 0})
        x,y = 0,0
        yield_func1(0) { |a| x = 42 } # should modify x
        yield_func2(0) { |y| y = 42 } # should not modify y
        {x, y}
        CODE
    end
  end

  describe :proc do
    it "handles many arguments" do
      IC.run_spec(<<-'CODE').should eq %("abc")
        p = ->(a : String, b : String, c : String){a+b+c}

        p.call "a", "b", "c"
        CODE
    end

    it "handles nested procs" do
      IC.run_spec(<<-'CODE').should eq %("abcdef")
        sum2 = ->(a : String, b : String){ a+b }
        sum3 = ->(a : String, b : String, c : String){ a + sum2.call(b,c) }
        sum5 = ->(a : String, b : String, c : String, d : String, e : String) do
          a + sum3.call(b,c, sum2.call(d,e))
        end

        sum5.call("a", sum2.call("b","c"), "d", "e", "f")
        CODE
    end

    it "handles closure" do
      IC.run_spec(<<-'CODE').should eq %(7)
        closure = 42
        p = ->(){ closure }
        closure = 7
        p.call
        CODE

      IC.run_spec(<<-'CODE').should eq %(7)
        closure = 42
        p = ->(x : Int32){ closure = x }
        p.call 7
        closure
        CODE
    end

    it "handles closure in def" do
      IC.run_spec(<<-'CODE').should eq %(6)
        x_ = 1
        p = ->(x : Int32, y : Int32){ x_+x+y }

        call_proc_func(p, 2, 3)
        CODE

      IC.run_spec(<<-'CODE').should eq %({42, 7})
        x = 42
        get_42 = closure_in_def(x)
        get_7 = closure_in_def(7)
        x = 0

        {get_42.call, get_7.call}
        CODE
    end

    it "takes proc argument as closure" do
      IC.run_spec(<<-'CODE').should eq %({42, 7})
        get = ->(x : Int32) do
          ->{x}
        end
        x = 42
        get_42 = get.call x
        get_7 = get.call 7
        x = 0

        {get_42.call, get_7.call}
        CODE
    end
  end
end
