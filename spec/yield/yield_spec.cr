require "./yield_helper"

describe :Yield do
  it "yields" do
    IC.run_spec(<<-'CODE').should eq %(10)
      yield_func1(1, 2, 3, 4) do |a, b, c, d|
        yield_func1(a+b, c, d) do |a, b, c|
          yield_func1(a+b, c) do |a,b|
            yield_func1(a+b) do |a|
              a[0]
            end
          end
        end
      end
      CODE
    IC.run_spec(<<-'CODE').should eq %(41)
      a = 42
      yield_func1(0) do |a|
        yield_func2(a[0] + 10) { |a| a }
      end
      CODE
  end

  it "breaks" do
    IC.run_spec(<<-'CODE').should eq %(3)
      i = 0
      while i < 10
        break if i == 3
        i += 1
      end
      i
      CODE

    IC.run_spec(<<-'CODE').should eq %({42, 31})
      yield_func1 do
        break 42, 31
      end
      CODE

    IC.run_spec(<<-'CODE').should eq %(7)
      yield_func1 do
        yield_func1 do
          break 42, 31
        end
        7
      end
      CODE
  end

  it "next" do
    IC.run_spec(<<-'CODE').should eq %(9)
      i = 0
      x = 0
      while i<6
        i += 1
        next if i % 2 == 0
        x += i
      end
      x
      CODE

    IC.run_spec(<<-'CODE').should eq %(9)
      x = 0
      times_func(6) do |i|
        next if i % 2 == 0
        x += i
      end
      x
      CODE
  end

  it "cover the good scope" do
    IC.run_spec(<<-'CODE').should eq %({42, 0})
      x, y = 0, 0
      yield_func1(0) { |a| x = 42 } # should modify x
      yield_func2(0) { |y| y = 42 } # should not modify y
      {x, y}
      CODE
  end
end
