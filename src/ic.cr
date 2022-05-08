require "compiler/crystal/interpreter"
require "./repl_interface/repl_interface"
require "./pry"
require "./errors"

module IC
  VERSION = "0.3.2"

  def self.run_file(repl, path, argv, debugger = false)
    repl.run_file(path, argv, debugger)
  end

  def self.run(repl)
    color = repl.program.color?

    repl.public_load_prelude

    input = ReplInterface::ReplInterface.new
    input.color = color
    input.repl = repl

    input.run do |expr|
      result = repl.run_next_code(expr)
      puts " => #{Highlighter.highlight(result.to_s, toggle: color)}"

      repl.pry = false # Explicitly exit the debugger

    rescue ex : Crystal::Repl::EscapingException
      print "Unhandled exception: "
      print ex
    rescue ex : Crystal::CodeError
      repl.clean

      ex.color = color
      ex.error_trace = true
      puts ex
    rescue ex : Exception
      ex.inspect_with_backtrace(STDOUT)
    end

    puts
  end
end

class Crystal::Repl
  def create_parser(code)
    Parser.new(
      code,
      string_pool: @program.string_pool,
      var_scopes: [@interpreter.local_vars.names_at_block_level_zero.to_set]
    )
  end

  def run_next_code(code)
    node = create_parser(code).parse
    interpret(node)
  end

  def run_file(filename, argv, debugger = false)
    @interpreter.argv = argv

    prelude_node = parse_prelude
    debugger_node = debugger ? Call.new(nil, "debugger") : Nop.new
    other_node = parse_file(filename)
    file_node = FileNode.new(other_node, filename)
    exps = Expressions.new([prelude_node, debugger_node, file_node] of ASTNode)

    interpret_and_exit_on_error(exps)

    # Explicitly call exit at the end so at_exit handlers run
    interpret_exit
  end

  def public_load_prelude
    load_prelude
  end

  def pry=(pry)
    @interpreter.pry = pry
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
