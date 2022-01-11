require "compiler/crystal/interpreter"
require "option_parser"
require "./repl_interface/repl_interface"
require "./pry"
require "./commands"
require "./errors"
require "./auto_completion"

repl = Crystal::Repl.new

OptionParser.parse do |parser|
  parser.banner = "Usage: ic [file] [--] [arguments]"

  parser.on "-v", "--version", "Print the version" do
    puts "version: #{IC::VERSION}"
    puts "crystal version: #{Crystal::Config.version}"
    exit
  end

  parser.on "-h", "--help", "Print this help" do
    puts parser
    exit
  end

  parser.on("-D FLAG", "--define FLAG", "Define a compile-time flag") do |flag|
    repl.program.flags << flag
  end

  parser.on "--no-color", "Disable colored output (Don't prevent interpreted code to emit colors)" do
    repl.program.color = false
  end

  # Doesn't work yet:
  # parser.on "--prelude FILE", "--prelude=FILE" "Use given file as prelude" do |file|
  #   repl.prelude = prelude
  # end

  parser.missing_option do |option_flag|
    STDERR.puts "ERROR: Missing value for option '#{option_flag}'."
    STDERR.puts parser
    exit(1)
  end

  parser.invalid_option do |option_flag|
    STDERR.puts "ERROR: Unkonwn option '#{option_flag}'."
    STDERR.puts parser
    exit(1)
  end
end

if ARGV[0]?
  IC.run_file repl, ARGV[0], ARGV[1..]
else
  IC.run repl
end

module IC
  VERSION = "0.3.0"

  def self.run_file(repl, path, argv)
    repl.run_file(path, argv)
  end

  def self.run(repl)
    color = repl.program.color?

    repl.public_load_prelude

    input = ReplInterface::ReplInterface.new
    input.color = color

    input.auto_complete = ->(receiver : String?, name : String) do
      auto_complete(repl, receiver, name)
    end

    input.run do |expr|
      result = repl.run_next_code(expr)
      puts " => #{Highlighter.highlight(result.to_s, toggle: color)}"
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
