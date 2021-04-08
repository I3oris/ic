require "./spec_helper"

describe ICR do
  it "run 1+1" do
    ICR.parse("1+1").run.result.should eq "2"
  end

  it "adds string" do
    ICR.parse(%("Hello "+"World"+"!")).run.result.should eq %("Hello World!")
  end

  it "gives the good object_id" do
    ICR.parse(<<-'CODE').run.result.should eq %(true)
      str = "Hello"
      pointerof(str).as(UInt64*).value == str.object_id
      CODE
  end

  it "declare a class" do
    ICR.parse(<<-'CODE').run.result.should eq %(nil)
      class Point
        property x
        property y
        property name

        def initialize(@x : Int32, @y : Int32, @name = "unnamed")
        end
      end
      CODE
  end

  it "run instance vars" do
    ICR.parse(<<-'CODE').run.result.should eq %("P")
      point = Point.new 42, 31
      point.name = "P"
      point.name
      # { point.x, point.y, point.name }
      CODE
  end
end
