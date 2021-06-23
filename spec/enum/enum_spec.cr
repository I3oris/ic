require "./enum_helper"

describe :Enum do
  it "declares a basic enum" do
    IC.run_spec(<<-'CODE').should eq %({0, 1, 2, 5, 3})
      {BasicEnum::A.value, BasicEnum::B.value, BasicEnum::C.value, BasicEnum::D.value, BasicEnum::E.value}
      CODE

    IC.run_spec(%(BasicEnum::A.class)).should eq %(BasicEnum)
  end

  it "declares a flags enum" do
    IC.run_spec(<<-'CODE').should eq %({1, 2, 4, 8, 16})
      {FlagsEnum::A.value, FlagsEnum::B.value, FlagsEnum::C.value, FlagsEnum::D.value, FlagsEnum::E.value}
      CODE
  end

  it "declares a typed enum" do
    IC.run_spec(<<-'CODE').should eq %({4_u8, 5_u8, 6_u8})
      {TypedEnum::A.value, TypedEnum::B.value, TypedEnum::C.value}
      CODE
  end

  it "convert symbol to enum" do
    IC.run_spec(<<-'CODE').should eq %({A, {B, C}, {foo: A, bar: B}})
      enum_func :a, :b, :c, foo: :a, bar: :b
      CODE
  end
end