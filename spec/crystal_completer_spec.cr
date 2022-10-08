require "./ic_spec_helper"

completer = IC::SpecHelper.crystal_completer

module IC
  describe CrystalCompleter do
    it "int literal" do
      completer.verify_completion(%(42.), should_be: "Int32")
      completer.verify_completion(%(42u8.), should_be: "UInt8")
      completer.verify_completion(%(111_222_333_444_555.), should_be: "Int64")
    end

    it "float literal" do
      completer.verify_completion(%(3.14.), should_be: "Float64")
      completer.verify_completion(%(1e-5_f32.), should_be: "Float32")
    end

    it "bool literal" do
      completer.verify_completion(%(true.), should_be: "Bool")
      completer.verify_completion(%(false.), should_be: "Bool")
    end

    it "symbol literal" do
      completer.verify_completion(%(:foo.), should_be: "Symbol")
      completer.verify_completion(%(:"foo bar".), should_be: "Symbol")
    end

    it "string literal" do
      completer.verify_completion(%("foo".), should_be: "String")
      completer.verify_completion("%(foo bar).", should_be: "String")
    end

    it "string literal with interpolation" do
      completer.verify_completion(%("foo #{1 + 1} bar".), should_be: "String")
      completer.verify_completion(<<-'CODE', should_be: "String")
        "multiline #{1 +
          2
        } ...".
        CODE
    end

    it "regex literal" do
      completer.verify_completion(%(/fo*/.), should_be: "Regex")
      completer.verify_completion(%(/fo*/im.), should_be: "Regex")
    end

    it "char literal" do
      completer.verify_completion(%('a'.), should_be: "Char")
      completer.verify_completion(%('\u{0123}'.), should_be: "Char")
    end

    it "tuple literal" do
      completer.verify_completion(%({1, '2', "3"}.), should_be: "Tuple(Int32, Char, String)")
      completer.verify_completion(%({1, {1, 2, {3}}}.), should_be: "Tuple(Int32, Tuple(Int32, Int32, Tuple(Int32)))")
    end

    it "named_tuple literal" do
      completer.verify_completion(%({foo: 1, bar: '2', "foo bar": "3"}.),
        should_be: %<NamedTuple(foo: Int32, bar: Char, "foo bar": String)>)
      completer.verify_completion(%({foo: 1, bar: {foo: 1, bar: 2, baz: {foo: 3}}}.),
        should_be: "NamedTuple(foo: Int32, bar: NamedTuple(foo: Int32, bar: Int32, baz: NamedTuple(foo: Int32)))")
    end

    it "array literal" do
      completer.verify_completion(%([1, '2', "3"].), should_be: "Array(Char | Int32 | String)")
      completer.verify_completion(%([1, [1, 2, [3]]].), should_be: "Array(Array(Array(Int32) | Int32) | Int32)")
    end

    it "something inside an array literal" do
      completer.verify_completion(%([1, '2'.), should_be: "Char")
      completer.verify_completion(%([1, '2', "3".), should_be: "String")
      completer.verify_completion(%([1, '2', [[["3".), should_be: "String")
    end

    it "hash literal" do
      completer.verify_completion(%({"foo" => 1, "bar" => '2', 42 => "3"}.),
        should_be: "Hash(Int32 | String, Char | Int32 | String)")
    end

    it "set literal" do
      completer.verify_completion(%(Set{1, '2', "3"}.), should_be: "Set(Char | Int32 | String)")
    end

    it "command literal" do
      completer.verify_completion(%(`ls`.), should_be: "String")
    end

    it "const literal" do
      completer.verify_completion(%(Crystal::VERSION.), should_be: "String")
    end

    it "const literal with scope" do
      completer.verify_completion(%(module Crystal; VERSION.), should_be: "String", with_scope: "Crystal")
    end

    it "proc literal" do
      completer.verify_completion(%(->{}.), should_be: "Proc(Nil)")
      completer.verify_completion(<<-'CODE', should_be: "Proc(Int32, Int32, String)")
        ->(x : Int32, y : Int32) do
          (x + y).to_s
        end.
        CODE
    end

    it "local var" do
      completer.verify_completion(<<-'CODE', should_be: "Int32")
        x = 42
        x.
        CODE
      completer.verify_completion(<<-'CODE', should_be: "(Int32 | Nil)")
        if rand < 0.5
          x = y = 42
        end
        x.
        CODE
    end

    it "call" do
      completer.verify_completion(<<-'CODE', should_be: "(Float64 | Nil)")
        def foo(x : Int32, y, z = true)
          if z
            x + y
          end
        end
        foo(42, 31.0).
        CODE
    end

    it "call with block" do
      completer.verify_completion(<<-'CODE', should_be: "(Array(Float64) | Nil)")
        def foo(x : Int32, y, z = true, &)
          if z
            yield x + y
          end
        end
        foo(42, 31.0) do |x|
          [x]
        end.
        CODE
    end

    it "chained call" do
      completer.verify_completion(%(42.to_s.to_i.to_s.size.), should_be: "Int32")
      completer.verify_completion(%(42.to_s(base: 2).to_i.to_s.size.), should_be: "Int32")
    end

    it "chained call with block" do
      completer.verify_completion(<<-'CODE', should_be: "Int32")
        [1, 2, 3].map(&.to_s).reduce(0) do |a, x|
          a + x.size
        end.
        CODE
    end

    it "parentheses expression" do
      completer.verify_completion(%((1+1).), should_be: "Int32")
      completer.verify_completion(<<-'CODE', should_be: "Int32")
        (
          x = 42
          1 + x + (3*7 - 10)
        ).
        CODE
    end

    it "if expression" do
      completer.verify_completion(<<-'CODE', should_be: "(Int32 | Nil)")
        if rand < 0.5
          1+1
        end.
        CODE
    end

    it "suffix if" do
      completer.verify_completion(<<-'CODE', should_be: "(Array(Int32) | Int32 | Regex | String | Symbol | Tuple(Int32) | Nil)")
        x = 42 if rand < 0.5
        x = :foo if rand < 0.5
        x = "bar" if rand < 0.5
        x = /baz/ if rand < 0.5
        x = (0) if rand < 0.5
        x = {0} if rand < 0.5
        x = [0] if rand < 0.5
        x.
        CODE

      completer.verify_completion(<<-'CODE', should_be: "(Int32 | Nil)")
        x = 42 if rand < 0.5 unless rand < 0.5 \
          if rand < 0.5
        x.
        CODE
    end

    it "case expression" do
      completer.verify_completion(<<-'CODE', should_be: "(Symbol | Nil)")
        case {42, "foo"}.sample
        when Int32
          :foo
        when String
        end.
        CODE
    end

    it "after .class expression" do
      completer.verify_completion(<<-'CODE', should_be: "Int32.class")
        x = 42.class
        x.
        CODE

      completer.verify_completion(<<-'CODE', should_be: "Int32.class", with_scope: "Foo")
        class Foo
          x = 42 . \
          class
          x.
        CODE
    end

    it "something inside a def" do
      completer.verify_completion(%(def foo; 42.), should_be: "Int32")
      completer.verify_completion(%(def foo; "foo".), should_be: "String")
      completer.verify_completion(%(def foo; [[42.), should_be: "Int32")
      completer.verify_completion(%(def foo; x = 42; x.), should_be: "Int32")
    end

    it "something with scope inside a def" do
      completer.verify_completion(%(class Foo; def foo; 42.), should_be: "Int32", with_scope: "Foo")
      completer.verify_completion(%(class Foo::Bar; class Baz; def foo; "foo".), should_be: "String", with_scope: "Foo::Bar::Baz")
      completer.verify_completion(%(class Foo::Bar; class ::Baz; def foo; [[42.), should_be: "Int32", with_scope: "Baz")
    end

    it "something with scope" do
      completer.verify_completion(%(class Foo; 42.), should_be: "Int32", with_scope: "Foo")
      completer.verify_completion(%(class Foo::Bar; class Baz;), should_be: "", with_scope: "Foo::Bar::Baz")
      completer.verify_completion(%(class Foo::Bar; class ::Baz;), should_be: "", with_scope: "Baz")
    end

    it "arguments inside a def" do
      completer.verify_completion(%(def foo(a); a.), should_be: "Any")
      completer.verify_completion(%(def foo(b : String); b.), should_be: "String")
      completer.verify_completion(%(def foo(c = 42); c.), should_be: "Int32")
      completer.verify_completion(%(def foo(a, b : String, c = 42); {a, b, c}.), should_be: "Tuple(Any, String, Int32)")
    end

    it "arguments inside a def with scope" do
      completer.verify_completion(<<-'CODE', should_be: "Tuple(Foo::Bar, String)", with_scope: "Foo")
        class Foo
          class Bar
          end

          def bar
            "bar"
          end

          def foo(x : Bar, y = bar)
            {x, y}.
        CODE
    end

    it "splat arguments inside a def" do
      completer.verify_completion(%(def foo(*splat); splat.), should_be: "Tuple(Any)")
      completer.verify_completion(%(def foo(*splat : Int32); splat.), should_be: "Tuple(Int32)")
      completer.verify_completion(%(def foo(*splat); splat.each &.), should_be: "Any")
      completer.verify_completion(%(def foo(a, b = 42, *splat, c = "foo"); {a, b, splat, c}.), should_be: "Tuple(Any, Int32, Tuple(Any), String)")
    end

    it "double splat arguments inside a def" do
      completer.verify_completion(%(def foo(**double_splat); double_splat.), should_be: "NamedTuple()")
      completer.verify_completion(%(def foo(a, b = 42, *splat, c = "foo", **double_splat); {a, b, splat, c, double_splat}.),
        should_be: "Tuple(Any, Int32, Tuple(Any), String, NamedTuple())")
    end

    it "recursive call" do
      completer.verify_completion(<<-'CODE', should_be: "Tuple(Int32, String)")
        def foo(x = 0) : String
          {x, foo(x + 1)}.
        CODE
    end

    it "something after Any" do
      completer.verify_completion(<<-'CODE', should_be: "Any")
        def foo(x)
          bar(x.baz.bam(0)).
        CODE
      completer.verify_completion(<<-'CODE', should_be: "Int32")
        def foo(x)
          y = bar(baz(x)).bam

          42.
        CODE
    end
  end
end
