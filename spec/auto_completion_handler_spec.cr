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

    it "case expression" do
      IC::Spec.verify_completion(handler, <<-'CODE', should_be: "(Symbol | Nil)")
        case {42, "foo"}.sample
        when Int32
          :foo
        when String
        end.
        CODE
    end
  end
end
