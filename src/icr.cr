{% unless flag?(:no_semantic) %}
  require "compiler/crystal/*"
  require "compiler/crystal/codegen/*"
  require "compiler/crystal/macros/*"
  require "compiler/crystal/semantic/*"
{% end %}
require "compiler/crystal/syntax"
require "./nodes"
require "./objects"
require "./primitives"
require "./highlighter"
require "./shell"
require "colorize"

{% unless flag?(:no_semantic) %}
  ICR.run_file "./program.cr"
{% end %}
ICR.run

def raise_error(arg)
  ::raise arg
end

module ICR
  VERSION = "0.1.0"

  {% unless flag?(:no_semantic) %}
    class_property program = Crystal::Program.new
  {% end %}
  class_property args_context = [{} of String => ICRObject]
  class_property receiver_context = [] of ICRObject

  # class_property type_context = [] of Crystal::Type

  def self.parse(text)
    ast_node = Crystal::Parser.parse text
    {% unless flag?(:no_semantic) %}
      ast_node = @@program.normalize(ast_node)
      ast_node = @@program.semantic(ast_node)
    {% end %}
    ast_node
  end

  def self.run_file(path)
    ICR.parse(File.read(path)).run
  end

  @@result : ICRObject? = nil

  def self.display_result
    if r = @@result
      print "\n => #{Highlighter.highlight(r.get_value.inspect, no_invitation: true)}"
    end
  end

  def self.run
    code = ""
    last_ast_node = nil

    Shell.new.run(->self.display_result) do |line|
      ast_node = ICR.parse(code + "\n" + line)
      run_last_expression(expressionize(last_ast_node), expressionize(ast_node))
      last_ast_node = ast_node
      code += "\n" + line

      :line
    rescue e
      @@result = nil
      if unterminated?(e)
        :multiline
      else
        puts
        puts e.message.colorize.yellow.bold
        :error
      end
    end
  end

  private def self.expressionize(node)
    if node.is_a? Crystal::Expressions
      node
    elsif node.nil?
      Crystal::Expressions.new
    else
      e = Crystal::Expressions.new
      e.expressions << node
      e
    end
  end

  private def self.run_last_expression(last_ast_node, ast_node)
    {% if flag?(:no_semantic) %}
      @@result = ICR.nil
      return
    {% end %}

    l_size = last_ast_node.expressions.size
    size = ast_node.expressions.size
    if l_size != size
      final = ast_node.expressions[l_size..].map(&.run)[-1]
      @@result = final
    end
  end

  private def self.unterminated?(error)
    error.message.in?({
      "expecting identifier 'end', not 'EOF'",
      "expecting token 'CONST', not 'EOF'",
      "expecting any of these tokens: IDENT, CONST, `, <<, <, <=, ==, ===, !=, =~, !~, >>, >, >=, +, -, *, /, //, !, ~, %, &, |, ^, **, [], []?, []=, <=>, &+, &-, &*, &** (not 'EOF')",
      "expecting token ')', not 'EOF'",
      "unexpected token: EOF",
      "unexpected token: EOF (expecting when, else or end)",
      "Unexpected EOF on heredoc identifier",
      "unexpected token: EOF (expecting ',', ';' or '\n')",
      "unterminated parenthesized expression",
      "Unterminated string literal", # <= U is upcase ^^
      "unterminated array literal",
      "unterminated macro",
      "Unterminated string interpolation",
      "unknown token: '\u{0}'",
    })
  end

  def self.run_method(receiver, a_def, args)
    if a_def.args.size != args.size
      raise_error "TODO: default values & named argument"
    end
    hash = {} of String => ICRObject
    a_def.args.each_with_index { |a, i| hash[a.name] = args[i] }

    @@args_context << hash
    @@receiver_context << receiver

    ret = a_def.body.run

    @@args_context.pop
    @@receiver_context.pop
    ret
  end

  def self.run_top_level_method(a_def, args)
    if a_def.args.size != args.size
      raise_error "TODO: default values & named argument"
    end
    hash = {} of String => ICRObject
    a_def.args.each_with_index { |a, i| hash[a.name] = args[i] }
    @@args_context << hash

    ret = a_def.body.run

    @@args_context.pop
    ret
  end

  def self.get_var(name)
    if name == "self"
      return @@receiver_context.last? || raise_error "self into a empty context"
    elsif h = @@args_context.last?
      # args = d.args.select(&.name == name)
      if value = h[name]?
        # puts "found #{name}"
        # i = d.args.index_of(arg[0])
        return value
      else
        raise_error "Cannot found def arg #{name}"
      end
    else
      raise_error "BUG: Context stack is empty"
    end
  end

  def self.assign_var(name, value)
    @@args_context.last[name] = value
  end
end
