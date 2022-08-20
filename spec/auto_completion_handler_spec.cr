require "spec"
require "./ic_spec_helper"

handler = IC::Spec.auto_completion_handler

describe IC::ReplInterface::AutoCompletionHandler do
  describe "found type of" do
    it "int literal" do
      IC::Spec.verify_completion(handler, %(42.), should_be: "Int32")
      IC::Spec.verify_completion(handler, %(42u8.), should_be: "UInt8")
      IC::Spec.verify_completion(handler, %(111_222_333_444_555.), should_be: "Int64")
    end

    it "float literal" do
      IC::Spec.verify_completion(handler, %(3.14.), should_be: "Float64")
      IC::Spec.verify_completion(handler, %(1e-5_f32.), should_be: "Float32")
    end

    it "bool literal" do
      IC::Spec.verify_completion(handler, %(true.), should_be: "Bool")
      IC::Spec.verify_completion(handler, %(false.), should_be: "Bool")
    end

    it "symbol literal" do
      IC::Spec.verify_completion(handler, %(:foo.), should_be: "Symbol")
      IC::Spec.verify_completion(handler, %(:"foo bar".), should_be: "Symbol")
    end

    it "string literal" do
      IC::Spec.verify_completion(handler, %("foo".), should_be: "String")
      IC::Spec.verify_completion(handler, "%(foo bar).", should_be: "String")
    end

    it "string literal with interpolation" do
      IC::Spec.verify_completion(handler, %("foo #{1 + 1} bar".), should_be: "String")
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "String")
        "multiline #{1 +
          2
        } ...".
        CODE
    end

    it "regex literal" do
      IC::Spec.verify_completion(handler, %(/fo*/.), should_be: "Regex")
      IC::Spec.verify_completion(handler, %(/fo*/im.), should_be: "Regex")
    end

    it "char literal" do
      IC::Spec.verify_completion(handler, %('a'.), should_be: "Char")
      IC::Spec.verify_completion(handler, %('\u{0123}'.), should_be: "Char")
    end

    it "tuple literal" do
      IC::Spec.verify_completion(handler, %({1, '2', "3"}.), should_be: "Tuple(Int32, Char, String)")
      IC::Spec.verify_completion(handler, %({1, {1, 2, {3}}}.), should_be: "Tuple(Int32, Tuple(Int32, Int32, Tuple(Int32)))")
    end

    it "named_tuple literal" do
      IC::Spec.verify_completion(handler, %({foo: 1, bar: '2', "foo bar": "3"}.),
        should_be: %<NamedTuple(foo: Int32, bar: Char, "foo bar": String)>)
      IC::Spec.verify_completion(handler, %({foo: 1, bar: {foo: 1, bar: 2, baz: {foo: 3}}}.),
        should_be: "NamedTuple(foo: Int32, bar: NamedTuple(foo: Int32, bar: Int32, baz: NamedTuple(foo: Int32)))")
    end

    it "array literal" do
      IC::Spec.verify_completion(handler, %([1, '2', "3"].), should_be: "Array(Char | Int32 | String)")
      IC::Spec.verify_completion(handler, %([1, [1, 2, [3]]].), should_be: "Array(Array(Array(Int32) | Int32) | Int32)")
    end

    it "something inside an array literal" do
      IC::Spec.verify_completion(handler, %([1, '2'.), should_be: "Char")
      IC::Spec.verify_completion(handler, %([1, '2', "3".), should_be: "String")
      IC::Spec.verify_completion(handler, %([1, '2', [[["3".), should_be: "String")
    end

    it "hash literal" do
      IC::Spec.verify_completion(handler, %({"foo" => 1, "bar" => '2', 42 => "3"}.),
        should_be: "Hash(Int32 | String, Char | Int32 | String)")
    end

    it "set literal" do
      IC::Spec.verify_completion(handler, %(Set{1, '2', "3"}.), should_be: "Set(Char | Int32 | String)")
    end

    it "command literal" do
      IC::Spec.verify_completion(handler, %(`ls`.), should_be: "String")
    end

    it "const literal" do
      IC::Spec.verify_completion(handler, %(Crystal::VERSION.), should_be: "String")
    end

    it "const literal with scope" do
      IC::Spec.verify_completion(handler, %(module Crystal; VERSION.), should_be: "String", with_scope: "Crystal")
    end

    it "proc literal" do
      IC::Spec.verify_completion(handler, %(->{}.), should_be: "Proc(Nil)")
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Proc(Int32, Int32, String)")
        ->(x : Int32, y : Int32) do
          (x + y).to_s
        end.
        CODE
    end

    it "local var" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Int32")
        x = 42
        x.
        CODE
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Int32 | Nil)")
        if rand < 0.5
          x = y = 42
        end
        x.
        CODE
    end

    it "call" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Float64 | Nil)")
        def foo(x : Int32, y, z = true)
          if z
            x + y
          end
        end
        foo(42, 31.0).
        CODE
    end

    it "call with block" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Array(Float64) | Nil)")
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
      IC::Spec.verify_completion(handler, %(42.to_s.to_i.to_s.size.), should_be: "Int32")
      IC::Spec.verify_completion(handler, %(42.to_s(base: 2).to_i.to_s.size.), should_be: "Int32")
    end

    it "chained call with block" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Int32")
        [1, 2, 3].map(&.to_s).reduce(0) do |a, x|
          a + x.size
        end.
        CODE
    end

    it "parentheses expression" do
      IC::Spec.verify_completion(handler, %((1+1).), should_be: "Int32")
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Int32")
        (
          x = 42
          1 + x + (3*7 - 10)
        ).
        CODE
    end

    it "if expression" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Int32 | Nil)")
        if rand < 0.5
          1+1
        end.
        CODE
    end

    it "suffix if" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Array(Int32) | Int32 | Regex | String | Symbol | Tuple(Int32) | Nil)")
        x = 42 if rand < 0.5
        x = :foo if rand < 0.5
        x = "bar" if rand < 0.5
        x = /baz/ if rand < 0.5
        x = (0) if rand < 0.5
        x = {0} if rand < 0.5
        x = [0] if rand < 0.5
        x.
        CODE

      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Int32 | Nil)")
        x = 42 if rand < 0.5 unless rand < 0.5 \
          if rand < 0.5
        x.
        CODE
    end

    it "case expression" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Symbol | Nil)")
        case {42, "foo"}.sample
        when Int32
          :foo
        when String
        end.
        CODE
    end

    it "after .class expression" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Int32.class")
        x = 42.class
        x.
        CODE

      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Int32.class", with_scope: "Foo")
        class Foo
          x = 42 . \
          class
          x.
        CODE
    end

    it "something inside a def" do
      IC::Spec.verify_completion(handler, %(def foo; 42.), should_be: "Int32")
      IC::Spec.verify_completion(handler, %(def foo; "foo".), should_be: "String")
      IC::Spec.verify_completion(handler, %(def foo; [[42.), should_be: "Int32")
      IC::Spec.verify_completion(handler, %(def foo; x = 42; x.), should_be: "Int32")
    end

    it "something with scope inside a def" do
      IC::Spec.verify_completion(handler, %(class Foo; def foo; 42.), should_be: "Int32", with_scope: "Foo")
      IC::Spec.verify_completion(handler, %(class Foo::Bar; class Baz; def foo; "foo".), should_be: "String", with_scope: "Foo::Bar::Baz")
      IC::Spec.verify_completion(handler, %(class Foo::Bar; class ::Baz; def foo; [[42.), should_be: "Int32", with_scope: "Baz")
    end

    it "something with scope" do
      IC::Spec.verify_completion(handler, %(class Foo; 42.), should_be: "Int32", with_scope: "Foo")
      IC::Spec.verify_completion(handler, %(class Foo::Bar; class Baz;), should_be: "", with_scope: "Foo::Bar::Baz")
      IC::Spec.verify_completion(handler, %(class Foo::Bar; class ::Baz;), should_be: "", with_scope: "Baz")
    end

    it "arguments inside a def" do
      IC::Spec.verify_completion(handler, %(def foo(a); a.), should_be: "Any")
      IC::Spec.verify_completion(handler, %(def foo(b : String); b.), should_be: "String")
      IC::Spec.verify_completion(handler, %(def foo(c = 42); c.), should_be: "Int32")
      IC::Spec.verify_completion(handler, %(def foo(a, b : String, c = 42); {a, b, c}.), should_be: "Tuple(Any, String, Int32)")
    end

    it "arguments inside a def with scope" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Tuple(Foo::Bar, String)", with_scope: "Foo")
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
      IC::Spec.verify_completion(handler, %(def foo(*splat); splat.), should_be: "Tuple(Any)")
      IC::Spec.verify_completion(handler, %(def foo(*splat : Int32); splat.), should_be: "Tuple(Int32)")
      IC::Spec.verify_completion(handler, %(def foo(*splat); splat.each &.), should_be: "Any")
      IC::Spec.verify_completion(handler, %(def foo(a, b = 42, *splat, c = "foo"); {a, b, splat, c}.), should_be: "Tuple(Any, Int32, Tuple(Any), String)")
    end

    it "double splat arguments inside a def" do
      IC::Spec.verify_completion(handler, %(def foo(**double_splat); double_splat.), should_be: "NamedTuple()")
      IC::Spec.verify_completion(handler, %(def foo(a, b = 42, *splat, c = "foo", **double_splat); {a, b, splat, c, double_splat}.),
        should_be: "Tuple(Any, Int32, Tuple(Any), String, NamedTuple())")
    end

    it "recursive call" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Tuple(Int32, String)")
        def foo(x = 0) : String
          {x, foo(x + 1)}.
        CODE
    end

    it "something after Any" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Any")
        def foo(x)
          bar(x.baz.bam(0)).
        CODE
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "Int32")
        def foo(x)
          y = bar(baz(x)).bam

          42.
        CODE
    end
  end

  describe "displays entries" do
    it "for many entries" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.open
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "Int32:\n" \
                   "abs         bits       clamp            \n" \
                   "abs2        bits_set?  class            \n" \
                   "bit         ceil       clone            \n" \
                   "bit_length  chr        crystal_type_id..\n",
          height: 5
      end
    end

    it "for many entries with larger screen" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.open
      handler.with_term_width(54) do
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "Int32:\n" \
                   "abs         bits       clamp            \n" \
                   "abs2        bits_set?  class            \n" \
                   "bit         ceil       clone            \n" \
                   "bit_length  chr        crystal_type_id..\n",
          height: 5
      end
      handler.with_term_width(55) do
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "Int32:\n" \
                   "abs         bits       clamp            day            \n" \
                   "abs2        bits_set?  class            days           \n" \
                   "bit         ceil       clone            digits         \n" \
                   "bit_length  chr        crystal_type_id  divisible_by?..\n",
          height: 5
      end
    end

    it "for many entries with higher screen" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.open
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "Int32:\n" \
                   "abs         bits       clamp            \n" \
                   "abs2        bits_set?  class            \n" \
                   "bit         ceil       clone            \n" \
                   "bit_length  chr        crystal_type_id..\n",
          height: 5
      end
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 6,
          display: "Int32:\n" \
                   "abs         bits_set?  clone            \n" \
                   "abs2        ceil       crystal_type_id  \n" \
                   "bit         chr        day              \n" \
                   "bit_length  clamp      days             \n" \
                   "bits        class      digits..         \n",
          height: 6
      end
    end

    it "for few entries" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("ab", "42.")
      handler.open
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "Int32:\n" \
                   "abs   \n" \
                   "abs2  \n",
          height: 3
      end
    end

    it "when closed" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.close
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "",
          height: 0
      end
    end

    it "when cleared" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.clear
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 5, clear_size: 3,
          display: "\n\n\n",
          height: 3
        IC::Spec.verify_completion_display handler, max_height: 5, clear_size: 5,
          display: "\n\n\n\n\n",
          height: 5
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "",
          height: 0
      end
    end

    it "when max height is zero" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.open
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 0,
          display: "",
          height: 0
      end
    end

    it "for no entry" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("___nop___", "42.")
      handler.open
      handler.with_term_width(40) do
        IC::Spec.verify_completion_display handler, max_height: 5,
          display: "",
          height: 0
      end
    end
  end

  describe "moves selection" do
    it "selection next" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.open
      handler.with_term_width(20) do
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   "abs   bit_length  \n" \
                   "abs2  bits        \n" \
                   "bit   bits_set?.. \n",
          height: 4

        handler.selection_next
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   ">abs  bit_length  \n" \
                   "abs2  bits        \n" \
                   "bit   bits_set?.. \n",
          height: 4

        3.times { handler.selection_next }
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   "abs   >bit_length \n" \
                   "abs2  bits        \n" \
                   "bit   bits_set?.. \n",
          height: 4
      end
    end

    it "selection next on next column" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.open
      6.times { handler.selection_next }
      handler.with_term_width(20) do
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   "abs   bit_length  \n" \
                   "abs2  bits        \n" \
                   "bit   >bits_set?..\n",
          height: 4

        handler.selection_next
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   "bit_length  >ceil  \n" \
                   "bits        chr    \n" \
                   "bits_set?   clamp..\n",
          height: 4
      end
    end

    it "selection previous" do
      handler = IC::Spec.auto_completion_handler
      handler.complete_on("", "42.")
      handler.open
      2.times { handler.selection_next }
      handler.with_term_width(20) do
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   "abs   bit_length  \n" \
                   ">abs2 bits        \n" \
                   "bit   bits_set?.. \n",
          height: 4

        handler.selection_previous
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   ">abs  bit_length  \n" \
                   "abs2  bits        \n" \
                   "bit   bits_set?.. \n",
          height: 4

        handler.selection_previous
        IC::Spec.verify_completion_display handler, max_height: 4,
          display: "Int32:\n" \
                   "nil?          \n" \
                   ">responds_to? \n" \
                   "              \n",
          height: 4
      end
    end
  end
end
