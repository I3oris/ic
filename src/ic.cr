require "compiler/crystal/**"
require "./repl_interface/repl_interface"
require "./commands"
require "./errors"

if ARGV[0]?
  IC.run_file ARGV[0], ARGV[1..]
else
  IC.run
end

module IC
  VERSION = "0.3.0"

  def self.run_file(path, argv)
    Crystal::Repl.new.run_file(path, argv)
  end

  def self.run
    repl = Crystal::Repl.new
    repl.public_load_prelude

    input = ReplInterface::ReplInterface.new

    input.auto_complete = ->(receiver : String?, name : String) do
      auto_complete(repl, receiver, name)
    end

    input.run do |expr|
      result = repl.run_next_code(expr)
      puts " => #{Highlighter.highlight(result.to_s)}"
    rescue ex : Crystal::Repl::EscapingException
      print "Unhandled exception: "
      print ex
    rescue ex : Crystal::CodeError
      repl.clean

      ex.color = true
      ex.error_trace = true
      puts ex
    rescue ex : Exception
      ex.inspect_with_backtrace(STDOUT)
    end

    puts
  end

  private def self.auto_complete(repl, receiver, name)
    results = [] of String

    if receiver && !receiver.empty?
      begin
        if 'A' <= receiver[0] <= 'Z' && receiver.index('.').nil?
          type_result = repl.run_next_code(receiver)
          context_type = type_result.type
        else
          type_result = repl.run_next_code("typeof(#{receiver})")
          context_type = type_result.type.instance_type
        end
      rescue
        return {"", results}
      end

      # Add keyword methods (.is_a?, .nil?, ...):
      Highlighter::KEYWORD_METHODS.each do |keyword|
        add_completion_result(results, keyword.to_s, name)
      end
    else
      context_type = repl.program

      # Add keywords:
      keywords = Highlighter::KEYWORDS + Highlighter::TRUE_FALSE_NIL + Highlighter::SPECIAL_VALUES
      keywords.each do |keyword|
        add_completion_result(results, keyword.to_s, name)
      end

      # Add top-level vars:
      vars = repl.@interpreter.local_vars.names_at_block_level_zero
      vars.each do |var_name|
        add_completion_result(results, var_name, name)
      end

      # Add types:
      repl.program.types.each do |type_name, _|
        add_completion_result(results, type_name, name)
      end
    end

    # Add defs from context_type:
    add_completion_defs(results, context_type, name)

    repl.clean
    {context_type.to_s, results}
  end

  private def self.add_completion_result(results, candidate, name)
    if candidate.starts_with? name
      results << candidate
    end
  end

  private def self.add_completion_defs(results, type, name)
    # Add def names from type:
    type.defs.try &.each do |def_name, def_|
      if def_.any? &.def.visibility.public?
        # Avoid special methods e.g `__crystal_raise`, `__crystal_malloc`...
        if !def_name.starts_with?('_') && def_name.starts_with? name
          results << def_name
        end
      end
    end

    # Recursively add def names from parents:
    type.parents.try &.each do |parent|
      add_completion_defs(results, parent, name)
    end
  end
end

class Crystal::Repl
  def run_next_code(code)
    parser = Parser.new(
      code,
      string_pool: @program.string_pool,
      var_scopes: [@interpreter.local_vars.names_at_block_level_zero.to_set]
    )
    node = parser.parse
    interpret(node)
  end

  def public_load_prelude
    load_prelude
  end

  def clean
    @main_visitor.clean
  end
end

class Crystal::MainVisitor
  def clean
    @exp_nest = 0 # Avoid the error "can't declare def dynamically"
    @in_type_args = 0
  end
end
