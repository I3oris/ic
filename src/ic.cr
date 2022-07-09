require "./repl"
require "option_parser"

module IC
  VERSION = "0.4.1"
end

repl = Crystal::Repl.new
debugger = false

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

  parser.on("-d", "--debugger", "If a file is given, start with the debugger") do
    debugger = true
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
    STDERR.puts "ERROR: Unknown option '#{option_flag}'."
    STDERR.puts parser
    exit(1)
  end
end

repl.program.color = false if ENV["NO_COLOR"]?.presence

if ARGV[0]?
  repl.run_file ARGV[0], ARGV[1..], debugger
else
  repl.bind_keyboard_interrupt
  repl.run
end
