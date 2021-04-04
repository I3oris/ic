require "compiler/crystal/*"
require "compiler/crystal/codegen/*"
require "compiler/crystal/macros/*"
require "compiler/crystal/semantic/*"
require "compiler/crystal/syntax"

require "./nodes"
require "./objects"
require "./primitives"
require "./execution"
require "./highlighter"
require "./shell"
require "colorize"
# require "gc"
# GC.disable

ICR.run_file "./prelude.cr"
ICR.run_file ARGV[0] if ARGV[0]?
ICR.run

class Crystal::MainVisitor
  # Don't raise when undersore:
  def visit(node : Underscore)
    if @in_type_args == 0
      # node.raise "can't read from _"
      node
    else
      node.raise "can't use underscore as generic type argument"
    end
  end
end

class Crystal::CleanupTransformer
  # Don't cleanup underscore:
  def untyped_expression(node, msg = nil)
    node
  end
end

class ICR::Error < Exception
end

def bug(msg)
  raise ICR::Error.new ("\nICR(BUG): " + msg).colorize.red.bold.to_s
end

def todo(msg)
  raise ICR::Error.new ("\nICR(TODO): " + msg).colorize.blue.bold.to_s
end

def icr_error(msg)
  raise ICR::Error.new ("\nICR: " + msg).colorize.magenta.bold.to_s
end

module ICR
  VERSION = "0.1.0"

  class_property program = Crystal::Program.new
  class_getter? busy = false

  def self.parse(text)
    ast_node = Crystal::Parser.parse text
    ast_node = @@program.normalize(ast_node)
    ast_node = @@program.semantic(ast_node)
    ast_node
  end

  def self.run_file(path)
    ICR.parse(File.read(path)).run
  end

  class_getter result : ICRObject = ICR.nil

  def self.display_result
    if r = @@result
      print "\n => #{Highlighter.highlight(r.result, no_invitation: true)}"
    end
  end

  def self.run
    code = ""
    last_ast_node = nil

    Shell.new.run(->self.display_result) do |line|
      ICR.clear_context
      ast_node = ICR.parse(code + "\n" + line)
      run_last_expression(expressionize(last_ast_node), expressionize(ast_node))
      last_ast_node = ast_node
      code += "\n" + line

      :line
    rescue Cancel
      @@busy = false
      next :line
    rescue e : ICR::Error
      puts e.message
      :error
    rescue e
      if unterminated?(e)
        :multiline
      else
        puts

        # this kind of message need to display more informations
        if e.message.try &.starts_with?("instantiating") || e.message == "expanding macro"
          puts e.colorize.yellow.bold
        else
          puts e.message.colorize.yellow.bold
        end
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
    {% if flag?(:_debug) %}
      puts
      ast_node.expressions[-1].print_debug
      puts
      puts
    {% end %}

    l_size = last_ast_node.expressions.size
    size = ast_node.expressions.size
    if l_size != size
      @@busy = true
      @@result = ast_node.expressions[l_size..].map(&.run)[-1]
      @@busy = false
    end
  end

  private def self.unterminated?(error)
    error.message.in?({
      "expecting identifier 'end', not 'EOF'",
      "expecting token 'CONST', not 'EOF'",
      "expecting any of these tokens: IDENT, CONST, `, <<, <, <=, ==, ===, !=, =~, !~, >>, >, >=, +, -, *, /, //, !, ~, %, &, |, ^, **, [], []?, []=, <=>, &+, &-, &*, &** (not 'EOF')",
      "expecting token ')', not 'EOF'",
      "expecting token ']', not 'EOF'",
      "expecting token '}', not 'EOF'",
      "expected '}' or named tuple name, not EOF",
      "unexpected token: EOF",
      "unexpected token: EOF (expecting when, else or end)",
      "unexpected token: EOF (expecting ',', ';' or '\n')",
      "Unexpected EOF on heredoc identifier",
      "unterminated parenthesized expression",
      "Unterminated string literal", # <= U is upcase ^^
      "unterminated array literal",
      "unterminated tuple literal",
      "unterminated macro",
      "Unterminated string interpolation",
      "invalid trailing comma in call",
      "unknown token: '\\u{0}'",
    }) || error.message.try &.matches? /Unterminated heredoc: can't find ".*" anywhere before the end of file/
  end
end
