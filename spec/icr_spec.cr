require "./spec_helper"

describe ICR do
  describe :primitives do
    it "run 1+1" do
      ICR.parse("1+1").run.result.should eq "2"
    end
  end

  describe :string do
    it "adds string" do
      ICR.parse(%("Hello "+"World"+"!")).run.result.should eq %("Hello World!")
    end
  end

  describe :array do
    it "fetch" do
      ICR.parse(%([0,42,5][1])).run.result.should eq %(42)
    end

    it "support many types'" do
      ICR.parse(%([0,:foo,"bar"][1])).run.result.should eq %(:foo)
    end
  end

  describe :classes do
    it "declare a class" do
      ICR.parse(<<-'CODE').run.result.should eq %(nil)
        class SpecClass
          property x
          property y
          property name

          def initialize(@x = 0, @y = 0, @name = "unnamed")
          end
        end
        CODE
    end

    it "declare a struct" do
      ICR.parse(<<-'CODE').run.result.should eq %(nil)
        struct SpecStruct
          property x
          property y
          property name

          def initialize(@x = 0, @y = 0, @name = "unnamed")
          end
        end
        CODE
    end

    it "inherit a class" do
      ICR.parse(<<-'CODE').run.result.should eq %(nil)
        class SpecSubclass1 < SpecClass
          @bar = "foo"
          property bar
        end

        class SpecSubclass2 < SpecClass
          @baz = :baz
          property baz
        end
        CODE
    end

    it "run instance vars" do
      ICR.parse(<<-'CODE').run.result.should eq %({42, 31, "hello"})
        foo = SpecClass.new 42, 31
        foo.name = "hello"
        { foo.x, foo.y, foo.name }
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

    # spec fail! : gets SpecClass+ instead of SpecSubclass1
    # it "preserve class on cast (unless Pointers)" do
    #   ICR.parse(<<-'CODE').run.result.should eq %({SpecSubclass1, Int32, Pointer(UInt64)})
    #     b = SpecSubclass1.new
    #     x = 42
    #     p = Pointer(Int32).new 42
    #     {
    #       b.as(SpecClass).class,
    #       x.as(Int32|String).class,
    #       p.as(UInt64*).class,
    #     }
    #     CODE
    # end
  end

  describe :union do
    # spec fail! : gets SpecClass+ instead of SpecClass
    # it "gives a good union virtual type" do
    #   ICR.parse(<<-'CODE').run.result.should eq %({SpecClass, true, false})
    #     foobar = SpecSubclass1|SpecSubclass2
    #     {foobar, foobar.is_a?(SpecClass.class), foobar == SpecClass}
    #     CODE
    # end

    it "declare a class with union ivars" do
      ICR.parse(<<-'CODE').run.result.should eq %(nil)
        class SpecUnionIvars
          @union_values : Int32|SpecStruct|Nil = nil
          @union_reference_like : SpecClass|String|Nil = nil
          @union_mixed : SpecStruct|SpecClass|Nil = nil

          property union_values, union_reference_like, union_mixed

          def all
            {@union_values, @union_reference_like, @union_mixed}
          end
        end
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
