# describe :generics do
#   IC.run_spec(%(LangGenericClass(Int32, 42, 31u8).type_vars)).should eq %({Int32, 42, 31_u8})
# end

describe :globals do
  # undefined method 'not_nil!' for Nil
  pending "use $~" do
    IC.run_spec(<<-'CODE').should eq %("foo")
      set_global("foo")
      $~
     CODE
  end
end

describe :assign do
  it "keep target and value independent" do
    IC.run_spec(<<-'CODE').should eq %({43, 42})
      x = 42
      y = x
      x += 1
      {x, y}
      CODE
  end
end

describe :pointerof do
  it "takes address of a local var" do
    IC.run_spec(<<-'CODE').should eq %({42, 31})
      a = 7
      p = pointerof(a)
      a = 42
      r1 = p.value # 42
      p.value = 31
      r2 = a # 31
      {r1, r2}
      CODE
  end
end

describe :out do
  # need prelude
  pending "takes a 'out' c-binding value" do
    IC.run_spec(<<-'CODE').should eq %({true, true, true})

      status = LibC.gettimeofday(out time, nil)
      {status == 0, time.tv_usec > 0, time.tv_sec > 0}
      CODE
  end
end
