require "compiler/crystal/*"
require "compiler/crystal/codegen/*"
require "compiler/crystal/macros/*"
require "compiler/crystal/semantic/*"
require "compiler/crystal/syntax"

require "./nodes"
require "./types"
require "./objects"
require "./literals"
require "./primitives"
require "./execution"
require "./fun"
require "./vars"
require "./highlighter"
# require "./shell"
require "./crystal_multiline_input"
require "./commands"
require "./errors"
require "colorize"
# IC.program.stdout = stdout
IC.run_file IC::PRELUDE_PATH

unless IC.running_spec?
  if ARGV[0]?
    IC.run_file ARGV[0]
  else
    IC.run
  end
end

module IC
  VERSION      = "0.2.0"
  PRELUDE_PATH = Path[__DIR__, "../ic_prelude.cr"].normalize

  class_property program = Crystal::Program.new
  class_getter? busy = false
  class_getter code_lines = [] of String

  def self.parse(expr)
    text = "\n"*@@code_lines.size + expr
    expr.each_line { |l| @@code_lines << l }

    ast_node = Crystal::Parser.parse text, def_vars: IC.declared_vars_syntax
    ast_node = @@program.normalize(ast_node)
    ast_node = @@program.semantic(ast_node)
    IC.update_vars
    ast_node
  end

  def self.run_file(path)
    @@program.filename = path.to_s
    IC.parse(File.read(path)).run
  rescue e
    e.display
  end

  def self.display_result(result)
    if result.nop?
      puts " => #{"✔".colorize.green}"
    else
      puts " => #{Highlighter.highlight(result.result)}"
    end
  end

  def self.run
    IC.underscore = IC.nil
    @@code_lines.clear
    @@program.filename = nil

    input = CrystalMultilineInput.new
    input.run do |expr|
      result = IC.parse(expr).run

      IC.underscore = result unless result.nop?

      display_result(result)
    rescue e
      on_error(e, expr)
    end

    puts
  end

  def self.on_error(e, expr)
    e.display
    @@code_lines.pop(expr.lines.size)
    IC.main_visitor.clean
  end

  def self.running_spec?
    false
  end
end

def debug_msg(msg)
end

# Print debug info on `make DEBUG=true`:
{% if flag? :_debug %}
  require "./debug.cr"
{% end %}

# Use one same main visitor instead of create a new one on each evaluation,
# so the meta-vars are keep:
module IC
  class_getter main_visitor do
    Crystal::MainVisitor.new(@@program)
  end
end

# Use that visitor here:
class Crystal::Program
  def visit_main(node, visitor = IC.main_visitor, process_finished_hooks = false, cleanup = true)
    previous_def
  end
end

# If a exception is raised during the main visit, the state of the visitor can be let inconsistent
# so, we must clean it:
class Crystal::MainVisitor
  def clean
    @exp_nest = 0 # Avoid the error "can't declare def dynamically"
    @in_type_args = 0
  end
end

# In some contexts vars are not keep, for example here:
# ```
# x = 42
# {% begin %}
#   x # considered undeclared
# {% end %}
# ```
#
# This happen because here an other visitor are used
# so we merge the declared vars with the vars of this visitor:
class Crystal::SemanticVisitor
  def initialize(@program, @vars = MetaVars.new)
    # previous_def:
    @current_type = @program
    @exp_nest = 0
    @in_lib = false
    @in_c_struct_or_union = false
    @in_is_a = false

    # # Added code:
    @vars.merge! IC.declared_vars
  end
end

# Invite the user to use '__' instead of '_':
class Crystal::MainVisitor
  def visit(node : Underscore)
    if @in_type_args == 0
      ic_error "'_' is reserved by crystal, use '__' instead"
    else
      node.raise "can't use underscore as generic type argument"
    end
  end
end

# `Transformer` applied between the syntax parsing and the semantics phase:
class IC::Transformer < Crystal::Transformer
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

# Call this transformer just after parsing:
# Note that the transformer will be executed on a `Require` node too.
class Crystal::Parser
  def parse
    IC::Transformer.new.transform(previous_def)
  end

  def parse(mode : ParseMode)
    IC::Transformer.new.transform(previous_def)
  end
end
