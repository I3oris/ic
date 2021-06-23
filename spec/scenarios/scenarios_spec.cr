require "./scenarios_helper"

describe :Scenarios do
  it "n° 1" do
    IC.run_spec("1+1").should eq "2"
  end

  it "n° 2" do
    IC.run_spec(<<-'CODE').should eq %({42, 31})
      class Point
        property x, y
        def initialize(@x = 42, @y = 31)
        end
      end

      p = Point.new

      class Point
        def xy
          {@x, @y}
        end
      end

      p.xy
      CODE
  end

  it "n° 3" do
    IC.run_spec(<<-'CODE').should eq %({nil, 42, nil, nil, nil, 31, 77, "hello"})
      class Foo
        property x, y, z, t
        @x : Nil
        def initialize(@y = 42,
                       @z : Int32 | Nil = nil,
                       @t : String | Nil = nil)
        end
      end
      foo = Foo.new
      x, y, z, t = foo.x, foo.y, foo.z, foo.t
      foo.x, foo.y, foo.z, foo.t = nil, 31, 77, "hello"

      {x ,y, z, t, foo.x, foo.y, foo.z, foo.t}
      CODE
  end

  it "n° 4" do
    IC.run_spec(<<-'CODE').should eq %({Int32, String, (Int32 | String)})
      x = 42
      t1 = typeof(x)
      x = "42"
      t2 = typeof(x)
      y = 42 || "42"
      t3 = typeof(y)
      {t1, t2, t3}
      CODE
  end

  it "n° 5" do
    IC.run_spec(<<-'CODE').should eq %(177_189_926)

      yield_func4(42, 7) do |a, b|
        if a < b
          yield_func3(a, b - 1) { |x| x }
        else
          yield_func3(b, yield_func4(1, 7) { |a| a + 1 }) do |x|
            x + a - b + (yield_func5(a) do |x|
              x2 = x//100
              if x2 == 0
                a*1000
              elsif x2 > 1000
                next x*7
              else
                x*7
              end
            end)
          end
        end
      end
      CODE
  end

  it "n° 6" do
    IC.run_spec(<<-'CODE').should eq %(617_918)
      x=42

      p1 = ->(a : Int32, b : Int32){a+b}
      p2 = ->(a : Int32, b : Int32, c : Int32){a+p1.call(b,c)}
      p3 = ->(a : Int32, b : Int32){ p2.call(b, p2.call(a,2*a,b), a-10 )}
      p4 = ->(p1_ : Proc(Int32,Int32,Int32,Int32), p2_ : Proc(Proc(Int32)), arg : Int32) do
        ->(y : Int32) do
          p3.call( p1_.call(arg+x,5,arg-4), p2_.call.call)*y
        end
      end

      p4.call(->(c : Int32, b : Int32, a : Int32) do
        p4.call(p2, ->{p1.partial(42, c)}, 7+c ).call 31+a+b
      end,->{p3.partial(1,2)},-1).call 7
      CODE
  end
end
