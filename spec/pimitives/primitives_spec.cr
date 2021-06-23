require "./primitives_helper"

describe :Primitives do
  it "allocates" do
    IC.run_spec(%(PrimitivesClass.new)).should match /#<PrimitivesClass:0x.*>/
    IC.run_spec(%(PrimitivesStruct.new)).should match /#<PrimitivesStruct>/
  end

  it "does binary op" do
    IC.run_spec(%(1+1)).should eq %(2)
    IC.run_spec(%(0.14+3)).should eq %(3.14)
    IC.run_spec(%(1-1)).should eq %(0)
    IC.run_spec(%(0.14-3)).should eq %(-2.86)
    IC.run_spec(%(3*4)).should eq %(12)
    IC.run_spec(%(3.14*4)).should eq %(12.56)
    # IC.run_spec(%(3/4)).should eq %(0.75)
    IC.run_spec(%(3.14/4)).should eq %(0.785)
    IC.run_spec(%(1 < 2)).should eq %(true)
    IC.run_spec(%(1 > 2)).should eq %(false)
    IC.run_spec(%(1 != 2)).should eq %(true)
    IC.run_spec(%(1 == 2)).should eq %(false)
    IC.run_spec(%(1 <= 2)).should eq %(true)
    IC.run_spec(%(1 >= 2)).should eq %(false)
    IC.run_spec(%('a' < 'b')).should eq %(true)
    IC.run_spec(%('a' > 'b')).should eq %(false)
    IC.run_spec(%('a' != 'b')).should eq %(true)
    IC.run_spec(%('a' == 'b')).should eq %(false)
    IC.run_spec(%('a' <= 'b')).should eq %(true)
    IC.run_spec(%('a' >= 'b')).should eq %(false)
    IC.run_spec(%(0b0010_1010 | 0b1100_0010 == 0b1110_1010)).should eq %(true)
    IC.run_spec(%(0b0010_1010 & 0b1100_0010 == 0b0000_0010)).should eq %(true)
    IC.run_spec(%(0b0010_1010 ^ 0b1100_0010 == 0b1110_1000)).should eq %(true)
  end

  # Need to include "int" to access MAX and MIN, but in practice spec works
  pending "does unsafe binary op" do
    {% for int in %w(UInt8 Int8 UInt16 Int16 UInt32 Int32 UInt64 Int64) %}
      IC.run_spec(%({{int.id}}::MAX &+ 1 == {{int.id}}::MIN)).should eq %(true)
      IC.run_spec(%({{int.id}}::MIN &- 1 == {{int.id}}::MAX)).should eq %(true)
    {% end %}
    IC.run_spec(%(0b1100_0010u8.unsafe_shr(3) == 0b0001_1000u8)).should eq %(true)
    IC.run_spec(%(0b1100_0010u8.unsafe_shl(3) == 0b0001_0000u8)).should eq %(true)
    IC.run_spec(%(1.unsafe_div(2))).should eq %(0)
    IC.run_spec(%(1.unsafe_mod(2))).should eq %(1)
    IC.run_spec(%(42.unsafe_div(5))).should eq %(8)
    IC.run_spec(%(42.unsafe_mod(5))).should eq %(2)
    IC.run_spec(%(42.unsafe_mod(-5))).should eq %(2)
    IC.run_spec(%(-42.unsafe_mod(5))).should eq %(-2)
    IC.run_spec(%(-42.unsafe_mod(-5))).should eq %(-2)
  end

  it "convert" do
    IC.run_spec(%(42.unsafe_chr)).should eq %('*')
    IC.run_spec(%(42u8.unsafe_chr)).should eq %('*')
    IC.run_spec(%(42i64.unsafe_chr)).should eq %('*')
    IC.run_spec(%('*'.ord)).should eq %(42)

    IC.run_spec(%(3.14_f32.to_f)).should eq %(3.140_000_104_904_175) # Normal imprecision with float
    IC.run_spec(%(3.14    .to_i)).should eq %(3)
    IC.run_spec(%(3.14    .to_u)).should eq %(3_u32)
    IC.run_spec(%(1       .to_u8)).should eq %(1_u8)
    IC.run_spec(%(42      .to_u16)).should eq %(42_u16)
    IC.run_spec(%(3.14    .to_u32)).should eq %(3_u32)
    IC.run_spec(%(7_i64   .to_u64)).should eq %(0x7)
    IC.run_spec(%(-1      .to_i8)).should eq %(-1_i8)
    IC.run_spec(%(42_i8   .to_i16)).should eq %(42_i16)
    IC.run_spec(%(-3.14   .to_i32)).should eq %(-3)
    IC.run_spec(%(7_u16   .to_i64)).should eq %(7_i64)
    IC.run_spec(%(42_u64  .to_f32)).should eq %(42.0_f32)
    IC.run_spec(%(-3.14   .to_f64)).should eq %(-3.14)
  end

  # Need to include "int" to access MAX and MIN,
  pending "convert (unchecked)" do
    IC.run_spec(%(-1i8.to_u8! == UInt8::MAX)).should eq %(true)
    IC.run_spec(%(-1i16.to_u16! == UInt16::MAX)).should eq %(true)
    IC.run_spec(%(-1i32.to_u32! == UInt32::MAX)).should eq %(true)
    IC.run_spec(%(-1i64.to_u64! == UInt64::MAX)).should eq %(true)
    IC.run_spec(%(3.14_f32.to_f64!)).should eq %(3.140_000_104_904_175)
    IC.run_spec(%(Float64::MAX.to_f32!)).should eq %(Infinity)
  end

  it "does pointer malloc" do
    IC.run_spec(<<-'CODE').should eq %({0, 0})
      p = Pointer(Int32).malloc 2
      { p[0], p[1] }
      CODE
  end

  it "realloc pointer" do
    IC.run_spec(<<-'CODE').should eq %({42, 31, -1, 7})
      p = Pointer(Int32).malloc 2
      p[0], p[1] = 42, 31
      p = p.realloc 4
      p[2], p[3] = -1, 7
      { p[0], p[1], p[2], p[3] }
      CODE
  end

  it "does pointer new && pointer address" do
    IC.run_spec(%(Pointer(Int32).new(0x42).address)).should eq %(0x42)
  end

  it "sets && gets pointers" do
    IC.run_spec(<<-'CODE').should eq %({42, 31})
      p = Pointer(Int32).malloc 2
      (p+1).value = 31
      p.value = 42
      { p.value, (p+1).value }
      CODE
  end

  it "adds pointers" do
    IC.run_spec(<<-'CODE').should eq %(0x9)
      p = Pointer(Int32).new(0x1)
      (p+2).address # 1 + 2*4
      CODE
  end

  it "subtracts pointers" do
    IC.run_spec(<<-'CODE').should eq %({-4_i64, 4_i64, -42_i64, 42_i64})
      p1 = Pointer(Int32).new(16)
      p2 = Pointer(Int32).new(32)
      p3 = Pointer(PrimitivesStruct).malloc(1)
      p4 = Pointer(PrimitivesStruct).new (p3+42).address
      {
        p1-p2,
        p2-p1,
        p3-p4,
        p4-p3,
      }
      CODE
  end

  it "index tuple" do
    IC.run_spec(<<-'CODE').should eq %({0, 'x', :foo, "bar"})
      t = {0, 'x', :foo, "bar"}
      {t[0], t[1], t[2], t[3]}
      CODE
  end

  it "gives the good object_id" do
    IC.run_spec(<<-'CODE').should eq %(true)
      foo = PrimitivesClass.new
      pointerof(foo).as(UInt64*).value == foo.object_id
      CODE
  end

  it "gives the good crystal_type_id" do
    IC.run_spec(<<-'CODE').should eq %(true)
      foo = PrimitivesClass.new
      Pointer(Int32).new(foo.object_id).value == foo.crystal_type_id
      CODE
  end

  it "gives the good class_crystal_instance_type_id" do
    IC.run_spec(<<-'CODE').should eq %(true)
      x = 42 || "foo"
      (x.class.crystal_instance_type_id == Int32.crystal_instance_type_id == x.crystal_type_id)
      CODE
  end

  it "gives class" do
    IC.run_spec(<<-'CODE').should eq %({Int32, Char, Symbol, String, PrimitivesClass, PrimitivesSubClass, PrimitivesStruct, PrimitivesEnum, Int32})
      x = 42 || "foo"
      {
        0.class,
        'x'.class,
        :foo.class,
        "bar".class,
        PrimitivesClass.new.class,
        PrimitivesSubClass.new.class,
        PrimitivesStruct.new.class,
        PrimitivesEnum.new(0).class,
        x.class,
      }
      CODE
  end

  it "convert symbol to string" do
    IC.run_spec(%(:foo.to_s)).should eq %("foo")
    IC.run_spec(%(:"$/*♥".to_s)).should eq %("$/*♥")
    IC.run_spec(%(:+.to_s)).should eq %("+")
  end

  it "gets enum value" do
    IC.run_spec(%(PrimitivesEnum::A.value)).should eq %(0)
    IC.run_spec(%(PrimitivesEnum::B.value)).should eq %(1)
    IC.run_spec(%(PrimitivesEnum::C.value)).should eq %(2)
  end

  it "creates new enum" do
    IC.run_spec(%(PrimitivesEnum.new 0)).should eq %(A)
    IC.run_spec(%(PrimitivesEnum.new 1)).should eq %(B)
    IC.run_spec(%(PrimitivesEnum.new 2)).should eq %(C)
    IC.run_spec(%(PrimitivesEnum.new 42)).should eq %(PrimitivesEnum:42)
  end

  it "call proc" do
    IC.run_spec(%(->(x : Int32){x+1}.call 1)).should eq %(2)
  end
end
