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

IC.run_file "./ic_prelude.cr"

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

  def self.parse(text)
    ast_node = Crystal::Parser.parse text, def_vars: IC.def_vars
    ast_node = @@program.normalize(ast_node)
    ast_node = @@program.semantic(ast_node)
    ast_node
  end

  def self.run_file(path)
    IC.parse(File.read(path)).run
  rescue e
    e.display
  end

  class_getter result : ICObject = IC.nop
  class_getter valid_result : ICObject = IC.nil

  def self.display_result
    if @@result.nop?
      print "\n => #{"✔".colorize.green}"
    else
      print "\n => #{Highlighter.highlight(@@result.result, no_invitation: true)}"
    end
  end

  def self.run
    header = "__ = nil\n"
    last_ast_node = nil

    Shell.new.run do |expr|
      next :line if expr.empty?

      IC.clear_callstack

      @@busy = true
      @@result = IC.parse(header + expr).run
      @@busy = false

      @@valid_result = @@result unless @@result.nop?
      IC.assign_var("__", @@valid_result)
      IC.program.@vars["__"] = Crystal::MetaVar.new "__", @@valid_result.type.cr_type

      # For each vars, add `var = uninitialized Type`,
      # this permit to keep vars on semantic for subsequent executions
      # (I haven't found a better way wet!)
      # The vars isn't really set, so declared vars keeps its values.
      header = IC.program.@vars.map do |name, value|
        "#{name} = uninitialized #{value.type}\n"
      end.join

      :line
    rescue Cancel
      @@busy = false
      :line
    rescue e : IC::CompileTimeError
      if e.unterminated?
        # let a change to the user to finish his text on the next line
        :multiline
      else
        e.display

        # We must reset vars on program to avoid error in repetition
        # i.e:
        # > x=42 # Ok
        # > x="42" # "Error must be Int32, not Int32|String", ok
        #
        # > 0 # Still "Error must be Int32, not Int32|String", because vars are not reseted
        IC.program.@vars.clear
        :error
      end
    rescue e
      e.display
      IC.program.@vars.clear
      :error
    end
  end

  def self.running_spec?
    false
  end
end

{% if flag? :_debug %}
  require "./debug.cr"
{% end %}

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
