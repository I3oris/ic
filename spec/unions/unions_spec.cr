require "./unions_helper"

describe :Unions do
  it "gives a good union virtual type" do
    IC.run_spec(<<-'CODE').should eq %({UnionClass, true, false})
      foobar = UnionSubClass1|UnionSubClass2
      {foobar, foobar.is_a?(UnionClass.class), foobar == UnionClass}
      CODE
  end

  it "support union ivars (1)" do
    IC.run_spec(<<-'CODE').should match /\{42, #<UnionClass:0x.*>, #<UnionStruct>\}/
      foo = UnionIvars.new
      foo.union_values = 42
      foo.union_reference_like = UnionClass.new
      foo.union_mixed = UnionStruct.new
      foo.all
      CODE
  end

  it "support union ivars (2)" do
    IC.run_spec(<<-'CODE').should match /\{#<UnionStruct>, "foo", #<UnionClass:0x.*>\}/
      foo = UnionIvars.new
      foo.union_values = UnionStruct.new
      foo.union_reference_like = "foo"
      foo.union_mixed = UnionClass.new
      foo.all
      CODE
  end

  it "dispatch primitives int" do
    IC.run_spec(%((1 || 2u8 || 3i64 ).class)).should eq %(Int32)
  end

  pending "dispatch classes" do
    IC.run_spec(<<-'CODE').should eq %({:UnionClass, :UnionSubClass1, :UnionClass, :UnionSubModule})
      var = [UnionClass.new, UnionSubClass1.new, UnionSubClass2.new, UnionSubSubClass.new]

      {
        var[0].f,
        var[1].f,
        var[2].f,
        var[3].f,
      }
    CODE
  end
end
