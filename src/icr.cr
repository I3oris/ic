require "compiler/crystal/*"
require "compiler/crystal/codegen/*"
require "compiler/crystal/macros/*"
require "compiler/crystal/semantic/*"
require "compiler/crystal/syntax"

require "./nodes"
require "./types"
require "./objects"
require "./primitives"
require "./execution"
require "./highlighter"
require "./shell"
require "./errors"
require "colorize"
# require "gc"
# GC.disable

ICR.run_file "./icr_prelude.cr"

if ARGV[0]?
  ICR.run_file ARGV[0]
else
  ICR.run
end

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
  rescue e
    e.display
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
      ICR.clear_callstack
      ast_node = ICR.parse(code + "\n" + line)
      run_last_expression(expressionize(last_ast_node), expressionize(ast_node))
      last_ast_node = ast_node
      code += "\n" + line

      :line
    rescue Cancel
      @@busy = false
      :line
    rescue e : ICR::CompileTimeError
      if e.unterminated?
        # let a change to the user to finish his text on the next line
        :multiline
      else
        e.display
        :error
      end
    rescue e
      e.display
      :error
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

  # Compare the last ASTNode with the current ASTNode, and run only
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
end
