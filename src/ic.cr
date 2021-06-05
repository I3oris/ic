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
require "./fun"
require "./vars"
require "./highlighter"
require "./shell"
require "./commands"
require "./errors"
require "colorize"

# IC.program.stdout = stdout
IC.run_file Path[__DIR__, "../ic_prelude.cr"].normalize

unless IC.running_spec?
  if ARGV[0]?
    IC.run_file ARGV[0]
  else
    IC.run
  end
end

module IC
  VERSION = "0.1.0"

  class_property program = Crystal::Program.new
  class_getter? busy = false
  class_getter code_lines = [] of String

  def self.parse(expr)
    text = "\n"*@@code_lines.size + expr
    expr.each_line { |l| @@code_lines << l }

    ast_node = Crystal::Parser.parse text, def_vars: IC.declared_vars_syntax
    ast_node = ICTransformer.new.transform(ast_node)
    ast_node = @@program.normalize(ast_node)
    ast_node = @@program.semantic(ast_node)
    ast_node
  end

  def self.run_file(path)
    @@program.filename = path.to_s
    IC.parse(File.read(path)).run
  rescue e
    e.display
  end

  @@result : ICObject = IC.nop

  def self.display_result
    if @@result.nop?
      puts " => #{"✔".colorize.green}"
    else
      puts " => #{Highlighter.highlight(@@result.result, no_invitation: true)}"
    end
  end

  def self.run
    IC.underscore = IC.nil
    @@code_lines.clear
    @@program.filename = nil
    # TODO redirect @@program.stdout

    Shell.new.run do |expr|
      @@busy = true
      @@result = IC.parse(expr).run
      @@busy = false

      IC.underscore = @@result unless @@result.nop?

      :line
    rescue Cancel
      @@busy = false
      :line
    rescue e : CompileTimeError
      if e.unterminated?
        @@code_lines.pop(expr.lines.size)
        # let a change to the user to finish his text on the next line
        :multiline
      else
        e.display
        @@code_lines.pop(expr.lines.size)
        :error
      end
    rescue e
      e.display
      @@code_lines.pop(expr.lines.size)
      :error
    end
  end

  def self.running_spec?
    false
  end
end

def debug_msg(msg)
end

{% if flag? :_debug %}
  require "./debug.cr"
{% end %}

# Force TopLevelVisitor and MainVisitor to keep the declared vars of the
# previous semantic:
class Crystal::SemanticVisitor
  def initialize(@program, @vars = MetaVars.new)
    # previous_def:
    @current_type = @program
    @exp_nest = 0
    @in_lib = false
    @in_c_struct_or_union = false
    @in_is_a = false

    # Added code:
    if @vars.empty?
      case self
      when TopLevelVisitor, MainVisitor
        @vars = IC.declared_vars
      end
    end
  end
end

# Alternative to the code above (safer & cleaner), but doesn't work with the following:
# ```
# x = 42
# {% begin %}
#   x # considered undeclared
# {% end %}
# ```

# class Crystal::Program
#   def visit_main(node, visitor = IC.main_visitor, process_finished_hooks = false, cleanup = true)
#     previous_def
#   end
# end

# module IC
#   def self.main_visitor
#     Crystal::MainVisitor.new(@@program, vars: IC.declared_vars)
#   end
# end

# Invite the user to use '__' instead of '_':
class Crystal::MainVisitor
  def visit(node : Underscore)
    if @in_type_args == 0
      ic_error "'_' is reserved by crystal, use '__' instead"
      node
    else
      node.raise "can't use underscore as generic type argument"
    end
  end
end

# class Crystal::CleanupTransformer
#   # Don't cleanup underscore:
#   def untyped_expression(node, msg = nil)
#     node
#   end
# end

class ICTransformer < Crystal::Transformer
  # Because crystal analyses the type of a constant only when used,
  # replace all occurrences of `FOO=some_exp` by `(FOO=some_exp; FOO)`
  def transform(node : Crystal::Assign)
    if (t = node.target).is_a? Crystal::Path
      Crystal::Expressions.new [node, t]
    else
      node
    end
  end

  # Replace also `private FOO=some_exp` by `(private FOO=some_exp; FOO)
  def transform(node : Crystal::VisibilityModifier)
    if (a = node.exp).is_a? Crystal::Assign && (t = a.target).is_a? Crystal::Path
      Crystal::Expressions.new [node, t]
    else
      node
    end
  end
end
