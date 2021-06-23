
describe :Const do
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
      CONST_FOO=(x="local")
      x
      CODE
  end

  it "executes semantics on initializers" do
    IC.run_spec(<<-'CODE').should eq %("foo")
      CONST_BAR=({{"foo"}})
      CODE
  end

  it "preserves initialization order" do
    IC.run_spec(<<-'CODE').should eq %({"(before A)(begin A)(B)(end A)(after A)(after B)", 2, 2, 1})
      class Trace
        @@trace = ""
        class_property trace
      end

      Trace.trace = "(before A)"

      CONST_A=(Trace.trace += "(begin A)"; a=CONST_B+1; Trace.trace += "(end A)"; a)

      Trace.trace += "(after A)"

      CONST_B=(Trace.trace += "(B)"; 1)

      Trace.trace += "(after B)"

      {Trace.trace, CONST_A, CONST_A, CONST_B}
      CODE
  end
end