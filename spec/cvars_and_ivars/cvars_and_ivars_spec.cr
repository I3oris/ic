require "./cvars_and_ivars_helper"

describe :"Instance Vars" do
  it "initializes" do
    IC.run_spec(<<-'CODE').should eq %({:foo, nil, :foo, nil, 7, :foo, nil, nil})
      a = IvarsClass.new
      b = IvarsSubClass.new
      c = IvarsGenericClass(Symbol, Float64).new
      {a.foo, a.bar, b.foo, b.bar, b.baz, c.foo, c.bar, c.t}
      CODE
  end

  it "changes their value" do
    IC.run_spec(<<-'CODE').should eq %({:FOO, "bar", :FOO2, "BAR", :FOO, "bar", :foo, nil, {:T, 3.14}})
      a = IvarsClass.new
      b = IvarsSubClass.new
      c = IvarsGenericClass(Symbol, Float64).new
      a.foo = :FOO
      a.bar = "bar"
      b.foo = :FOO2
      b.bar = "BAR"
      b.baz = a
      c.t = {:T, 3.14}
      baz = b.baz.as(IvarsClass)
      {a.foo, a.bar, b.foo, b.bar, baz.foo, baz.bar, c.foo, c.bar, c.t}
      CODE
  end
end

describe :"Class vars" do
  it "initializes" do
    IC.run_spec(<<-'CODE').should eq %({nil, "bar", nil, "sub_bar", nil, "bar"})
      {
        CvarsClass.c_foo,
        CvarsClass.c_bar,
        CvarsSubClass1.c_foo,
        CvarsSubClass1.c_bar,
        CvarsSubClass2.c_foo,
        CvarsSubClass2.c_bar,
      }
      CODE

    IC.run_spec(<<-'CODE').should eq %({:a, "bar", nil, "b", :c, :d})
      CvarsClass.c_foo = :a
      CvarsSubClass1.c_bar = "b"
      CvarsSubClass2.c_foo = :c
      CvarsSubClass2.c_bar = :d
      {
        CvarsClass.c_foo,
        CvarsClass.c_bar,
        CvarsSubClass1.c_foo,
        CvarsSubClass1.c_bar,
        CvarsSubClass2.c_foo,
        CvarsSubClass2.c_bar,
      }
      CODE
  end
end
