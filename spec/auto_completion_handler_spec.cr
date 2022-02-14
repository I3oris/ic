require "spec"
require "../src/ic"

handler = IC::ReplInterface::AutoCompletionHandler.new

describe IC::ReplInterface::AutoCompletionHandler do
  describe "parse_receiver_code:" do
    it "parse var" do
      handler.parse_receiver_code(%(var.)).should eq %(var)
      handler.parse_receiver_code(%(x + y + var.)).should eq %(var)
      handler.parse_receiver_code(%(foo bar var.)).should eq %(var)
    end

    it "parse chained call without argument" do
      handler.parse_receiver_code(%(foo.bar.baz.)).should eq %(foo.bar.baz)
      handler.parse_receiver_code(%(x + y + foo.bar.baz.)).should eq %(foo.bar.baz)

      handler.parse_receiver_code(%(foo bar foo.bar.baz.)).should eq(%(foo.bar.baz))
    end

    it "parse simple string" do
      handler.parse_receiver_code(%("string".)).should eq %("string")
      handler.parse_receiver_code(%(x + y + "string".)).should eq %("string")
      handler.parse_receiver_code(%(foo bar "string".foo.bar.)).should eq %("string".foo.bar)
    end

    it "parse string with escapes" do
      handler.parse_receiver_code(%q(foo "foo \" ".)).should eq %q("foo \" ")
      handler.parse_receiver_code(%q(foo "\"\'\x00\"".)).should eq %q("\"'\u0000\"")
      handler.parse_receiver_code(%q(foo "}]".)).should eq %q("}]")
    end

    it "parse string with interpolation" do
      handler.parse_receiver_code(%q(foo "foo#{bar}baz".)).should eq %q("foo#{bar}baz")
      handler.parse_receiver_code(%q(foo "foo#{"bar"}baz".)).should eq %q("foobarbaz")
      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        foo "foo#{
          "bar"+
          "baz"
        }bam".
        CODE
        "foo#{"bar" + "baz"}bam"
        EXPECTED_RECEIVER
    end

    it "parse string with interpolation 2" do
      handler.parse_receiver_code(%q("foo#{foo.bar.)).should eq %q(foo.bar)
      handler.parse_receiver_code(%q("foo #{bar} #{baz.)).should eq %q(baz)
      handler.parse_receiver_code(%q("#{"foo #{"bar".)).should eq %q("bar")
    end

    it "parse tuple" do
      handler.parse_receiver_code(%({1, 2, 3}.)).should eq %({1, 2, 3})
      handler.parse_receiver_code(%({1, 2, 3.)).should eq %(3)
      handler.parse_receiver_code(%(x + y + {1, 2, 3}.)).should eq %({1, 2, 3})
    end

    it "parse named tuple" do
      handler.parse_receiver_code(%({foo: 1, bar: 2, baz: 3}.)).should eq %({foo: 1, bar: 2, baz: 3})
      handler.parse_receiver_code(%({foo: 1, bar: 2, baz: 3.)).should eq %(3)
      handler.parse_receiver_code(%(x + y + {foo: 1, bar: 2, baz: 3}.)).should eq %({foo: 1, bar: 2, baz: 3})
    end

    it "parse array" do
      handler.parse_receiver_code(%([1, 2, 3].)).should eq %([1, 2, 3])
      handler.parse_receiver_code(%([1, 2, 3.)).should eq %(3)
      handler.parse_receiver_code(%(x + y + [1, 2, 3].)).should eq %([1, 2, 3])
      handler.parse_receiver_code(%(foo bar [1, 2, 3].foo.bar.)).should eq %([1, 2, 3].foo.bar) # pending: parsed as `bar[1,2,3].foo.bar`
    end

    it "parse array index" do
      handler.parse_receiver_code(%(array[x].)).should eq %(array[x])
      handler.parse_receiver_code(%(x + y + array[x].)).should eq %(array[x])
      handler.parse_receiver_code(%(foo bar array[x].foo.bar.)).should eq %(array[x].foo.bar)
    end

    it "parse array index 2" do
      handler.parse_receiver_code(%(foo bar array[x, y, z].foo.bar.)).should eq %(array[x, y, z].foo.bar)
      handler.parse_receiver_code(%([1,2]+array[array[1], [1,2,3][y], z].)).should eq %(array[array[1], [1, 2, 3][y], z])
    end

    # Don't work at all:
    it "parse array index 3" do
      handler.parse_receiver_code(%(x + [x, y, z][0].)).should eq %([x, y, z][0])
      handler.parse_receiver_code(%(x + [x, y, z][x][y][z].)).should eq %([x, y, z][x][y][z])
      handler.parse_receiver_code(%(x + [x]+[[x][x], [y][y], ][[x]][y][[[z]]].)).should eq %([[x][x], [y][y]][[x]][y][[[z]]])
    end

    it "parse call with block" do
      handler.parse_receiver_code(%(x + foo do; end.)).should eq %(foo do\nend)
      handler.parse_receiver_code(%(x + foo a do; end.)).should eq %(foo(a) do\nend)
      handler.parse_receiver_code(%(x + foo a, b, c do; end.)).should eq %(foo(a, b, c) do\nend)
      handler.parse_receiver_code(%(x + foo(a, b, c) do; end.)).should eq %(foo(a, b, c) do\nend)
    end

    it "parse call with block and receiver" do
      handler.parse_receiver_code(%(x + foo.bar.baz do; end.)).should eq %(foo.bar.baz do\nend)
      handler.parse_receiver_code(%(x + foo.bar.baz a do; end.)).should eq %(foo.bar.baz(a) do\nend)
      handler.parse_receiver_code(%(x + foo.bar.baz a, b, c do; end.)).should eq %(foo.bar.baz(a, b, c) do\nend)
      handler.parse_receiver_code(%(x + foo.bar.baz(a, b, c) do; end.)).should eq %(foo.bar.baz(a, b, c) do\nend)
    end

    it "parse nested call with block" do
      handler.parse_receiver_code(%(x + foo bar do; end.)).should eq %(foo(bar) do\nend)
      handler.parse_receiver_code(%(x + foo bar baz do; end.)).should eq %(bar(baz) do\nend)      # <= here it's bar that is invoked with a block
      handler.parse_receiver_code(%(x + foo bar,baz do; end.)).should eq %(foo(bar, baz) do\nend) # <= here it's foo that is invoked with a block
      handler.parse_receiver_code(%(x + foo(bar baz) do; end.)).should eq %(foo(bar(baz)) do\nend)
      handler.parse_receiver_code(%(x + foo(bar,baz) do; end.)).should eq %(foo(bar, baz) do\nend)
    end

    it "parse nested call with block 2" do
      handler.parse_receiver_code(%(x + foo(bar do; end) do; end.)).should eq %(foo(bar do\nend) do\nend)
      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x + foo bar, baz + foo do |x, y|
          foo do; end
        end.foo do
          bar baz do; x end
        end.bar x, y, x + y do
        end.foo.
        CODE
        ((foo(bar, baz + foo) do |x, y|
          foo do
          end
        end).foo do
          bar(baz) do
            x
          end
        end.bar(x, y, x + y) do
        end).foo
        EXPECTED_RECEIVER
    end

    it "parse nested call with block 3" do
      handler.parse_receiver_code(%(x + bar foo 1 + bar do; end.)).should eq %(foo(1 + bar) do\nend) # <= here it's foo that is invoked with a block
      handler.parse_receiver_code(%(x + foo bar, 2 do; end.)).should eq %(foo(bar, 2) do\nend)
      handler.parse_receiver_code(%(x + foo 1, bar do; end.)).should eq %(foo(1, bar) do\nend)
      handler.parse_receiver_code(%(x + foo 1, bar 1 do; end.)).should eq %(bar(1) do\nend)                              # <= here it's bar that is invoked with a block
      handler.parse_receiver_code(%(x + bar foo a+1,1,3,[+2,a] do; end.)).should eq %(foo(a + 1, 1, 3, [+2, a]) do\nend) # <= here it's foo that is invoked with a block
      handler.parse_receiver_code(%(x + foo foo.bar bar.baz do; end.)).should eq %(foo(foo.bar(bar.baz)) do\nend)
    end

    it "parse assing" do
      handler.parse_receiver_code(%(x = foo.)).should eq %(foo)
      handler.parse_receiver_code(%(x : Foo = foo.)).should eq %(foo)
      handler.parse_receiver_code(%(foo.x = foo.)).should eq %(foo)
    end
    it "parse range" do
      handler.parse_receiver_code(%(foo ..1.)).should eq %(1)
      handler.parse_receiver_code(%(foo ..\(1.)).should eq %(1)
      handler.parse_receiver_code(%(foo (..1).)).should eq %((..1))
    end

    it "parse if" do
      handler.parse_receiver_code(%(x = if true.)).should eq(%(true))

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = if true
          42.
        CODE
        42
        EXPECTED_RECEIVER

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = if true
          42
        else
          "foo".
        CODE
        "foo"
        EXPECTED_RECEIVER

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = if true
          42
        else
          "foo"
        end.
        CODE
        if true
          42
        else
          "foo"
        end
        EXPECTED_RECEIVER
    end

    it "parse while" do
      handler.parse_receiver_code(%(x = while true.)).should eq(%(true))

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = while true
          42.
        CODE
        42
        EXPECTED_RECEIVER

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = while true
          42
        end.
        CODE
        while true
          42
        end
        EXPECTED_RECEIVER
    end

    it "parse case" do
      handler.parse_receiver_code(%(x = case "foo".)).should eq(%("foo"))

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = case "foo"
          when 42.
        CODE
        42
        EXPECTED_RECEIVER

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = case "foo"
          when 42
            "bar".
        CODE
        "bar"
        EXPECTED_RECEIVER

      handler.parse_receiver_code(<<-'CODE').should eq(<<-'EXPECTED_RECEIVER')
        x = case "foo"
          when 42
            "bar"
          else
            "baz".
        CODE
        "baz"
        EXPECTED_RECEIVER
    end
  end
end
