require "compiler/crystal/interpreter"
require "./repl_interface/repl_interface"
require "./pry"
require "./crystal_errors"

class Crystal::Repl
  getter? prelude_complete = false

  def run
    color = @program.color?

    prelude_complete_channel = Channel(Int32).new
    spawn do
      load_prelude
      prelude_complete_channel.send(1)
    end

    repl_interface = IC::ReplInterface::ReplInterface.new
    repl_interface.color = color
    repl_interface.output = output = @interpreter.pry_interface.output = @program.stdout
    repl_interface.repl = self

    repl_interface.run do |expr|
      prelude_complete_channel.receive && prelude_complete_channel.close unless prelude_complete_channel.closed?

      result = run_next_code(expr, initial_line_number: repl_interface.line_number - repl_interface.lines.size - 1)
      output.puts " => #{IC::Highlighter.highlight(result.to_s, toggle: color)}"

      # Explicitly exit the debugger
      @interpreter.pry = false
    rescue ex : Crystal::Repl::KeyboardInterrupt
      output.puts
    rescue ex : Crystal::Repl::EscapingException
      output.print "Unhandled exception: "
      output.print ex
    rescue ex : Crystal::CodeError
      self.clean

      ex.color = color
      ex.error_trace = true
      output.puts ex
    rescue ex : Exception
      ex.inspect_with_backtrace(output)
    end

    output.puts
  end

  def create_parser(code, initial_line_number = 0)
    parser = Parser.new(
      code,
      string_pool: @program.string_pool,
      var_scopes: [@interpreter.local_vars.names_at_block_level_zero.to_set]
    )
    parser.filename = TopLevelExpressionVirtualFile.new(source: code, initial_line_number: initial_line_number)
    parser
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

  def load_prelude
    @prelude_complete = false
    previous_def
    @prelude_complete = true
  end

  private def run_next_code(code, initial_line_number = 0)
    node = create_parser(code, initial_line_number).parse
    interpret(node)
  end

  # Cleans the stack and the main visitor
  private def clean
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
