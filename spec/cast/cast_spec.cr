require "../unions/unions_helper"

describe :Cast do
  # got UnionClass+ instead of UnionSubClass1

  pending "casts the good class" do
    IC.run_spec(<<-'CODE').should eq %({UnionSubClass1, Int32, Pointer(UInt64)})
      b = UnionSubClass1.new
      x = 42
      p = Pointer(Int32).new 42
      {
        b.as(UnionClass).class,
        x.as(Int32|String).class,
        p.as(UInt64*).class,
      }
      CODE
  end
end