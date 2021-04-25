require "./spec_helper"

describe IC do
  describe :scenarios do
    it "runs scenario 1" do
      IC.parse("1+1").run.result.should eq "2"
    end

    it "runs scenario 2" do
      IC.parse(<<-'CODE').run.result.should eq %({42, 31})
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
      IC.parse(<<-'CODE').run.result.should eq %({nil, 42, nil, nil, nil, 31, 77, "hello"})
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
  end

  describe :string do
    it "creates empty string" do
      IC.parse(%("")).run.result.should eq %("")
    end

    it "adds string" do
      IC.parse(%("Hello "+"World"+"!")).run.result.should eq %("Hello World!")
    end
  end

  describe :array do
    it "fetch" do
      IC.parse(%([0,42,5][1])).run.result.should eq %(42)
    end

    it "supports many types'" do
      IC.parse(%([0,:foo,"bar"][1])).run.result.should eq %(:foo)
    end
  end

  describe :primitives do
    it "allocates" do
      IC.parse(%(SpecClass.new)).run.result.should match /#<SpecClass:0x.*>/
      IC.parse(%(SpecStruct.new)).run.result.should match /#<SpecStruct>/
    end

    it "does binary op" do
      IC.parse(%(1+1)).run.result.should eq %(2)
      IC.parse(%(0.14+3)).run.result.should eq %(3.14)
      IC.parse(%(1-1)).run.result.should eq %(0)
      IC.parse(%(0.14-3)).run.result.should eq %(-2.86)
      IC.parse(%(3*4)).run.result.should eq %(12)
      IC.parse(%(3.14*4)).run.result.should eq %(12.56)
      # IC.parse(%(3/4)).run.result.should eq %(0.75)
      IC.parse(%(3.14/4)).run.result.should eq %(0.785)
      IC.parse(%(1 < 2)).run.result.should eq %(true)
      IC.parse(%(1 > 2)).run.result.should eq %(false)
      IC.parse(%(1 != 2)).run.result.should eq %(true)
      IC.parse(%(1 == 2)).run.result.should eq %(false)
      IC.parse(%(1 <= 2)).run.result.should eq %(true)
      IC.parse(%(1 >= 2)).run.result.should eq %(false)
      IC.parse(%('a' < 'b')).run.result.should eq %(true)
      IC.parse(%('a' > 'b')).run.result.should eq %(false)
      IC.parse(%('a' != 'b')).run.result.should eq %(true)
      IC.parse(%('a' == 'b')).run.result.should eq %(false)
      IC.parse(%('a' <= 'b')).run.result.should eq %(true)
      IC.parse(%('a' >= 'b')).run.result.should eq %(false)
      IC.parse(%(0b0010_1010 | 0b1100_0010 == 0b1110_1010)).run.result.should eq %(true)
      IC.parse(%(0b0010_1010 & 0b1100_0010 == 0b0000_0010)).run.result.should eq %(true)
      IC.parse(%(0b0010_1010 ^ 0b1100_0010 == 0b1110_1000)).run.result.should eq %(true)
    end

    # Need to include "int" to access MAX and MIN, but in practice spec works
    pending "does unsafe binary op" do
      {% for int in %w(UInt8 Int8 UInt16 Int16 UInt32 Int32 UInt64 Int64) %}
        IC.parse(%({{int.id}}::MAX &+ 1 == {{int.id}}::MIN)).run.result.should eq %(true)
        IC.parse(%({{int.id}}::MIN &- 1 == {{int.id}}::MAX)).run.result.should eq %(true)
      {% end %}
      IC.parse(%(0b1100_0010u8.unsafe_shr(3) == 0b0001_1000u8)).run.result.should eq %(true)
      IC.parse(%(0b1100_0010u8.unsafe_shl(3) == 0b0001_0000u8)).run.result.should eq %(true)
      IC.parse(%(1.unsafe_div(2))).run.result.should eq %(0)
      IC.parse(%(1.unsafe_mod(2))).run.result.should eq %(1)
      IC.parse(%(42.unsafe_div(5))).run.result.should eq %(8)
      IC.parse(%(42.unsafe_mod(5))).run.result.should eq %(2)
      IC.parse(%(42.unsafe_mod(-5))).run.result.should eq %(2)
      IC.parse(%(-42.unsafe_mod(5))).run.result.should eq %(-2)
      IC.parse(%(-42.unsafe_mod(-5))).run.result.should eq %(-2)
    end

    it "convert" do
      IC.parse(%(42.unsafe_chr)).run.result.should eq %('*')
      IC.parse(%(42u8.unsafe_chr)).run.result.should eq %('*')
      IC.parse(%(42i64.unsafe_chr)).run.result.should eq %('*')
      IC.parse(%('*'.ord)).run.result.should eq %(42)

      IC.parse(%(3.14_f32.to_f)).run.result.should eq %(3.140_000_104_904_175) # Normal imprecision with float
      IC.parse(%(3.14    .to_i)).run.result.should eq %(3)
      IC.parse(%(3.14    .to_u)).run.result.should eq %(3_u32)
      IC.parse(%(1       .to_u8)).run.result.should eq %(1_u8)
      IC.parse(%(42      .to_u16)).run.result.should eq %(42_u16)
      IC.parse(%(3.14    .to_u32)).run.result.should eq %(3_u32)
      IC.parse(%(7_i64   .to_u64)).run.result.should eq %(0x7)
      IC.parse(%(-1      .to_i8)).run.result.should eq %(-1_i8)
      IC.parse(%(42_i8   .to_i16)).run.result.should eq %(42_i16)
      IC.parse(%(-3.14   .to_i32)).run.result.should eq %(-3)
      IC.parse(%(7_u16   .to_i64)).run.result.should eq %(7_i64)
      IC.parse(%(42_u64  .to_f32)).run.result.should eq %(42.0_f32)
      IC.parse(%(-3.14   .to_f64)).run.result.should eq %(-3.14)
    end

    # Need to include "int" to access MAX and MIN,
    pending "convert (unchecked)" do
      IC.parse(%(-1i8.to_u8! == UInt8::MAX)).run.result.should eq %(true)
      IC.parse(%(-1i16.to_u16! == UInt16::MAX)).run.result.should eq %(true)
      IC.parse(%(-1i32.to_u32! == UInt32::MAX)).run.result.should eq %(true)
      IC.parse(%(-1i64.to_u64! == UInt64::MAX)).run.result.should eq %(true)
      IC.parse(%(3.14_f32.to_f64!)).run.result.should eq %(3.140_000_104_904_175)
      IC.parse(%(Float64::MAX.to_f32!)).run.result.should eq %(Infinity)
    end

    it "does pointer malloc" do
      IC.parse(<<-'CODE').run.result.should eq %({0, 0})
        p = Pointer(Int32).malloc 2
        { p[0], p[1] }
        CODE
    end

    it "realloc pointer" do
      IC.parse(<<-'CODE').run.result.should eq %({42, 31, -1, 7})
        p = Pointer(Int32).malloc 2
        p[0], p[1] = 42, 31
        p = p.realloc 4
        p[2], p[3] = -1, 7
        { p[0], p[1], p[2], p[3] }
        CODE
    end

    it "does pointer new && pointer address" do
      IC.parse(%(Pointer(Int32).new(0x42).address)).run.result.should eq %(0x42)
    end

    it "sets && gets pointers" do
      IC.parse(<<-'CODE').run.result.should eq %({42, 31})
        p = Pointer(Int32).malloc 2
        (p+1).value = 31
        p.value = 42
        { p.value, (p+1).value }
        CODE
    end

    it "adds pointers" do
      IC.parse(<<-'CODE').run.result.should eq %(0x9)
        p = Pointer(Int32).new(0x1)
        (p+2).address
        CODE
    end

    it "subtracts pointers" do
      IC.parse(<<-'CODE').run.result.should eq %({-4_i64, 4_i64, -42_i64, 42_i64})
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
      IC.parse(<<-'CODE').run.result.should eq %({0, 'x', :foo, "bar"})
        t = {0,'x',:foo,"bar"}
        {t[0],t[1],t[2],t[3]}
        CODE
    end

    it "gives the good object_id" do
      IC.parse(<<-'CODE').run.result.should eq %(true)
        foo = SpecClass.new 0,0
        pointerof(foo).as(UInt64*).value == foo.object_id
        CODE
    end

    it "gives the good crystal_type_id" do
      IC.parse(<<-'CODE').run.result.should eq %(true)
        foo = SpecClass.new 0,0
        Pointer(Int32).new(foo.object_id).value == foo.crystal_type_id
        CODE
    end

    it "gives the good class_crystal_instance_type_id" do
      IC.parse(<<-'CODE').run.result.should eq %(true)
        x = 42 || "foo"
        (x.class.crystal_instance_type_id == Int32.crystal_instance_type_id == x.crystal_type_id)
        CODE
    end

    it "gives class" do
      IC.parse(<<-'CODE').run.result.should eq %({Int32, Char, Symbol, String, SpecClass, SpecSubClass1, SpecStruct, Int32})
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
      IC.parse(%(:foo.to_s)).run.result.should eq %("foo")
      IC.parse(%(:"$/*♥".to_s)).run.result.should eq %("$/*♥")
      IC.parse(%(:+.to_s)).run.result.should eq %("+")
    end
  end

  describe :classes do
    it "supports instance vars" do
      IC.parse(<<-'CODE').run.result.should eq %({42, 31, "hello"})
        foo = SpecClass.new 42, 31
        foo.name = "hello"
        { foo.x, foo.y, foo.name }
        CODE
    end

    # got SpecClass+ instead of SpecSubClass1
    pending "preserve class on cast (unless Pointers)" do
      IC.parse(<<-'CODE').run.result.should eq %({SpecSubClass1, Int32, Pointer(UInt64)})
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

  describe :const do
    it "declare a CONST" do
      IC.parse(%(FOO = "foo")).run.result.should eq %("foo")
      IC.parse(%(FOO)).run.result.should eq %("foo")
    end
  end

  describe :union do
    # got SpecClass+ instead of SpecClass
    pending "gives a good union virtual type" do
      IC.parse(<<-'CODE').run.result.should eq %({SpecClass, true, false})
        foobar = SpecSubClass1|SpecSubClass2
        {foobar, foobar.is_a?(SpecClass.class), foobar == SpecClass}
        CODE
    end

    it "support union ivars (1)" do
      IC.parse(<<-'CODE').run.result.should match /\{42, #<SpecClass:0x.*>, #<SpecStruct>\}/
        foo = SpecUnionIvars.new
        foo.union_values = 42
        foo.union_reference_like = SpecClass.new
        foo.union_mixed = SpecStruct.new
        foo.all
        CODE
    end

    it "support union ivars (2)" do
      IC.parse(<<-'CODE').run.result.should match /\{#<SpecStruct>, "foo", #<SpecClass:0x.*>\}/
        foo = SpecUnionIvars.new
        foo.union_values = SpecStruct.new
        foo.union_reference_like = "foo"
        foo.union_mixed = SpecClass.new
        foo.all
        CODE
    end
  end
end
