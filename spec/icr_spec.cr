require "./spec_helper"

describe ICR do
  describe :scenarios do
    it "runs scenario 1" do
      ICR.parse("1+1").run.result.should eq "2"
    end

    it "runs scenario 2" do
      ICR.parse(<<-'CODE').run.result.should eq %({42, 31})
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
      ICR.parse(<<-'CODE').run.result.should eq %({nil, 42, nil, nil, nil, 31, 77, "hello"})
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
      ICR.parse(%("")).run.result.should eq %("")
    end

    it "adds string" do
      ICR.parse(%("Hello "+"World"+"!")).run.result.should eq %("Hello World!")
    end
  end

  describe :array do
    it "fetch" do
      ICR.parse(%([0,42,5][1])).run.result.should eq %(42)
    end

    it "supports many types'" do
      ICR.parse(%([0,:foo,"bar"][1])).run.result.should eq %(:foo)
    end
  end

  describe :primitives do
    it "allocates" do
      ICR.parse(%(SpecClass.new)).run.result.should match /#<SpecClass:0x.*>/
      ICR.parse(%(SpecStruct.new)).run.result.should match /#<SpecStruct>/
    end

    it "does binary op" do
      ICR.parse(%(1+1)).run.result.should eq %(2)
      ICR.parse(%(0.14+3)).run.result.should eq %(3.14)
      ICR.parse(%(1-1)).run.result.should eq %(0)
      ICR.parse(%(0.14-3)).run.result.should eq %(-2.86)
      ICR.parse(%(3*4)).run.result.should eq %(12)
      ICR.parse(%(3.14*4)).run.result.should eq %(12.56)
      # ICR.parse(%(3/4)).run.result.should eq %(0.75)
      ICR.parse(%(3.14/4)).run.result.should eq %(0.785)
      ICR.parse(%(1 < 2)).run.result.should eq %(true)
      ICR.parse(%(1 > 2)).run.result.should eq %(false)
      ICR.parse(%(1 != 2)).run.result.should eq %(true)
      ICR.parse(%(1 == 2)).run.result.should eq %(false)
      ICR.parse(%(1 <= 2)).run.result.should eq %(true)
      ICR.parse(%(1 >= 2)).run.result.should eq %(false)
      ICR.parse(%('a' < 'b')).run.result.should eq %(true)
      ICR.parse(%('a' > 'b')).run.result.should eq %(false)
      ICR.parse(%('a' != 'b')).run.result.should eq %(true)
      ICR.parse(%('a' == 'b')).run.result.should eq %(false)
      ICR.parse(%('a' <= 'b')).run.result.should eq %(true)
      ICR.parse(%('a' >= 'b')).run.result.should eq %(false)
    end

    it "does pointer malloc" do
      ICR.parse(<<-'CODE').run.result.should eq %({0, 0})
        p = Pointer(Int32).malloc 2
        { p.value, (p+1).value }
        CODE
    end

    it "does pointer new && pointer address" do
      ICR.parse(%(Pointer(Int32).new(0x42).address)).run.result.should eq %(0x42)
    end

    it "sets && gets pointers" do
      ICR.parse(<<-'CODE').run.result.should eq %({42, 31})
        p = Pointer(Int32).malloc 2
        (p+1).value = 31
        p.value = 42
        { p.value, (p+1).value }
        CODE
    end

    it "adds pointers" do
      ICR.parse(<<-'CODE').run.result.should eq %(0x9)
        p = Pointer(Int32).new(0x1)
        (p+2).address
        CODE
    end

    it "index tuple" do
      ICR.parse(<<-'CODE').run.result.should eq %({0, 'x', :foo, "bar"})
        t = {0,'x',:foo,"bar"}
        {t[0],t[1],t[2],t[3]}
        CODE
    end

    it "gives the good object_id" do
      ICR.parse(<<-'CODE').run.result.should eq %(true)
        foo = SpecClass.new 0,0
        pointerof(foo).as(UInt64*).value == foo.object_id
        CODE
    end

    it "gives the good crystal_type_id" do
      ICR.parse(<<-'CODE').run.result.should eq %(true)
        foo = SpecClass.new 0,0
        Pointer(Int32).new(foo.object_id).value == foo.crystal_type_id
        CODE
    end

    it "gives the good class_crystal_instance_type_id" do
      ICR.parse(<<-'CODE').run.result.should eq %(true)
        x = 42 || "foo"
        (x.class.crystal_instance_type_id == Int32.crystal_instance_type_id == x.crystal_type_id)
        CODE
    end

    it "gives class" do
      ICR.parse(<<-'CODE').run.result.should eq %({Int32, Char, Symbol, String, SpecClass, SpecSubClass1, SpecStruct, Int32})
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
  end

  describe :classes do
    it "supports instance vars" do
      ICR.parse(<<-'CODE').run.result.should eq %({42, 31, "hello"})
        foo = SpecClass.new 42, 31
        foo.name = "hello"
        { foo.x, foo.y, foo.name }
        CODE
    end

    # got SpecClass+ instead of SpecSubClass1
    pending "preserve class on cast (unless Pointers)" do
      ICR.parse(<<-'CODE').run.result.should eq %({SpecSubClass1, Int32, Pointer(UInt64)})
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
      ICR.parse(%(FOO = "foo")).run.result.should eq %("foo")
      ICR.parse(%(FOO)).run.result.should eq %("foo")
    end
  end

  describe :union do
    # got SpecClass+ instead of SpecClass
    pending "gives a good union virtual type" do
      ICR.parse(<<-'CODE').run.result.should eq %({SpecClass, true, false})
        foobar = SpecSubClass1|SpecSubClass2
        {foobar, foobar.is_a?(SpecClass.class), foobar == SpecClass}
        CODE
    end

    it "support union ivars (1)" do
      ICR.parse(<<-'CODE').run.result.should match /\{42, #<SpecClass:0x.*>, #<SpecStruct>\}/
        foo = SpecUnionIvars.new
        foo.union_values = 42
        foo.union_reference_like = SpecClass.new
        foo.union_mixed = SpecStruct.new
        foo.all
        CODE
    end

    it "support union ivars (2)" do
      ICR.parse(<<-'CODE').run.result.should match /\{#<SpecStruct>, "foo", #<SpecClass:0x.*>\}/
        foo = SpecUnionIvars.new
        foo.union_values = SpecStruct.new
        foo.union_reference_like = "foo"
        foo.union_mixed = SpecClass.new
        foo.all
        CODE
    end
  end
end
