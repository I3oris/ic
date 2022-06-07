require "compiler/crystal/interpreter"
require "./repl_interface/repl_interface"
require "./pry"
require "./errors"

module IC
  VERSION = "0.4.1"

  def self.run_file(repl, path, argv, debugger = false)
    repl.run_file(path, argv, debugger)
  end

  def self.run(repl)
    color = repl.program.color?

    repl.public_load_prelude
    repl.bind_keyboard_interrupt

    input = ReplInterface::ReplInterface.new
    input.color = color
    input.repl = repl

    input.run do |expr|
      result = repl.run_next_code(expr, initial_line_number: input.line_number - input.lines.size - 1)
      puts " => #{Highlighter.highlight(result.to_s, toggle: color)}"

      # Explicitly exit the debugger
      repl.pry = false
    rescue ex : Crystal::Repl::KeyboardInterrupt
      puts
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
  def create_parser(code, initial_line_number = 0)
    parser = Parser.new(
      code,
      string_pool: @program.string_pool,
      var_scopes: [@interpreter.local_vars.names_at_block_level_zero.to_set]
    )
    parser.filename = TopLevelExpressionVirtualFile.new(source: code, initial_line_number: initial_line_number)
    parser
  end

  def run_next_code(code, initial_line_number = 0)
    node = create_parser(code, initial_line_number).parse
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

  # Cleans the stack and the main visitor
  def clean
    @main_visitor.clean
  end

  def reset
    @program = Program.new
    @context.reset(@program)

    @nest = 0
    @incomplete = false
    @line_number = 1
    @main_visitor = MainVisitor.new(@program)

    @interpreter = Interpreter.new(@context)

    @buffer = ""
    load_prelude
  end

  class KeyboardInterrupt < Exception
  end

  def bind_keyboard_interrupt
    @interpreter.bind_keyboard_interrupt
  end
end

class Crystal::Repl::Interpreter
  @keyboard_interrupt = false

  # Interrupts the running program and raises `KeyboardInterrupt`.
  def keyboard_interrupt
    # We enable pry to be able to handle interruption.
    @pry = @keyboard_interrupt = true
  end

  # The interpreter to stop when `Signal::INT` is caught.
  @@keyboard_interrupt_target : Crystal::Repl::Interpreter?

  # Associates `Signal::INT` to an interruption of `self`.
  def bind_keyboard_interrupt
    @@keyboard_interrupt_target = self

    # We use `libC.signal` because `Signal.trap` doesn't trigger handler while the process is busy
    # (e.g. an infinite loop)
    LibC.signal ::Signal::INT.value, ->(_value : Int32) do
      # Inside the LibC signal handler, only a very limited of function are allowed
      # Here it's safe because we only use an `if` and set instance vars.
      @@keyboard_interrupt_target.try &.keyboard_interrupt
    end
  end
end

class Crystal::Repl::Context
  def reset(@program)
    @program.flags << "interpreted"
  end
end

class Crystal::MainVisitor
  def clean
    @exp_nest = 0 # Avoid the error "can't declare def dynamically"
    @in_type_args = 0
  end
end
