require "./spec_helper"

describe ICR do
  it "run 1+1" do
    ICR.parse("1+1").run.result.should eq "2"
  end

  it "adds string" do
    ICR.parse(%("Hello "+"World"+"!")).run.result.should eq %("Hello World!")
  end

  it "declare a class" do
    ICR.parse(<<-'CODE').run.result.should eq %(nil)
      class Foo
        property x
        property y
        property name

        def initialize(@x : Int32, @y : Int32, @name = "unnamed")
        end
      end
      CODE
  end

  it "run instance vars" do
    ICR.parse(<<-'CODE').run.result.should eq %("hello")
      foo = Foo.new 42, 31
      foo.name = "hello"
      foo.name
      # { foo.x, foo.y, foo.name }
      CODE
  end

  it "gives the good object_id" do
    ICR.parse(<<-'CODE').run.result.should eq %(true)
      foo = Foo.new 0,0
      pointerof(foo).as(UInt64*).value == foo.object_id
      CODE
  end

  it "gives the good crystal_type_id" do
    ICR.parse(<<-'CODE').run.result.should eq %(true)
      foo = Foo.new 0,0
      Pointer(Int32).new(foo.object_id).value == foo.crystal_type_id
      CODE
  end
end
