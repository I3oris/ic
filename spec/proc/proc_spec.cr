require "./proc_helper"

describe :Proc do
  it "handles many arguments" do
    IC.run_spec(<<-'CODE').should eq %("abc")
      p = ->(a : String, b : String, c : String){ a + b + c }

      p.call "a", "b", "c"
      CODE
  end

  it "handles nested procs" do
    IC.run_spec(<<-'CODE').should eq %("abcdef")
      sum2 = ->(a : String, b : String){ a + b }
      sum3 = ->(a : String, b : String, c : String){ a + sum2.call(b, c) }
      sum5 = ->(a : String, b : String, c : String, d : String, e : String) do
        a + sum3.call(b, c, sum2.call(d, e))
      end

      sum5.call("a", sum2.call("b", "c"), "d", "e", "f")
      CODE
  end

  it "handles closure" do
    IC.run_spec(<<-'CODE').should eq %(7)
      closure = 42
      p = ->(){ closure }
      closure = 7
      p.call
      CODE

    IC.run_spec(<<-'CODE').should eq %(7)
      closure = 42
      p = ->(x : Int32){ closure = x }
      p.call 7
      closure
      CODE
  end

  it "handles closure in def" do
    IC.run_spec(<<-'CODE').should eq %(6)
      x_ = 1
      p = ->(x : Int32, y : Int32){ x_ + x + y }

      proc_call(p, 2, 3)
      CODE

    IC.run_spec(<<-'CODE').should eq %({42, 7})
      x = 42
      get_42 = proc_closure_in_def(x)
      get_7 = proc_closure_in_def(7)
      x = 0

      {get_42.call, get_7.call}
      CODE
  end

  it "takes proc argument as closure" do
    IC.run_spec(<<-'CODE').should eq %({42, 7})
      get = ->(x : Int32) do
        ->{x}
      end
      x = 42
      get_42 = get.call x
      get_7 = get.call 7
      x = 0

      {get_42.call, get_7.call}
      CODE
  end
end