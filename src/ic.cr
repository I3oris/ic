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
