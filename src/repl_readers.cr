require "reply"
require "./crystal_completer"
require "./crystal_parser_nest"
require "./highlighter"

module IC
  abstract class CrystalReader < Reply::Reader
    @highlighter = Highlighter.new

    def continue?(expression)
      create_parser(expression).parse
      false
    rescue e : Crystal::CodeError
      e.unterminated? ? true : false
    end

    def format(expression)
      Crystal.format(expression).chomp rescue nil
    end

    def highlight(expression)
      @highlighter.highlight(expression)
    end

    def indentation_level(expression_before_cursor)
      parser = create_parser(expression_before_cursor)
      parser.parse rescue nil

      parser.type_nest + parser.def_nest + parser.fun_nest + parser.control_nest + parser.case_nest
    end

    def word_delimiters
      # `"`, `:`, `'`, are not a delimiter because symbols and strings should be treated as one word.
      # '=', !', '?' are not a delimiter because they could make part of method name.
      /[ \n\t\+\-\*\/,;@&%<>\^\\\[\]\(\)\{\}\|\.\~]/
    end

    def reindent_line(line)
      case line.strip
      when "end", ")", "]", "}"
        0
      when "in", "when"
        -1 if in_a_case?
      when "else", "elsif", "rescue", "ensure"
        -1
      else
        nil
      end
    end

    def save_in_history?(expression : String)
      expression.presence
    end

    def read_loop(&)
      super do |expr|
        case expr
        when "# clear_history", "#clear_history"
          self.history.clear
          print_status(true)
        when "# reset", "#reset"
          status = (self.reset; true) rescue false
          print_status(status)
        when .blank?
          # Nothing
        else
          yield expr
        end
      end
    end

    private def create_parser(code)
      Crystal::Parser.new(code)
    end

    private def print_status(status)
      icon = status ? "✔".colorize(:green) : "×".colorize(:red)
      self.output.puts " => #{icon}"
    end

    private def in_a_case?
      parser = create_parser(@editor.expression_before_cursor)
      parser.parse rescue nil

      parser.case_nest > 0
    end
  end

  class ReplReader < CrystalReader
    @crystal_completer = CrystalCompleter.new
    @repl : Crystal::Repl

    def initialize(@repl)
      super()
    end

    def prompt(io, line_number, _color?)
      io << "ic(#{Crystal::Config.version}):"
      io << sprintf("%03d", line_number)
      io << "> "
    end

    def auto_complete(name_filter, expression)
      return "", [] of String unless @repl.prelude_complete? # Prevent to trigger auto-completion while running the prelude.

      # Set auto-completion context from repl, allow auto-completion to take account of previously defined types, methods and local vars.
      @crystal_completer.set_context(@repl)
      @crystal_completer.complete_on(name_filter, expression)
    end

    def auto_completion_display_title(io : IO, title : String)
      io << @highlighter.highlight(title)
    end

    private def create_parser(code)
      @repl.create_parser(code)
    end

    def reset
      super
      @repl.reset
    end
  end

  class PryReader < CrystalReader
    @crystal_completer = CrystalCompleter.new

    def prompt(io, line_number, color?)
      io << "ic(#{Crystal::Config.version}):"
      io << "pry".colorize(:magenta).toggle(color?)
      io << "> "
    end

    def set_context(local_vars, program, main_visitor, special_commands)
      @crystal_completer.set_context(local_vars, program, main_visitor, special_commands)
    end

    def auto_complete(name_filter, expression)
      @crystal_completer.complete_on(name_filter, expression)
    end

    def on_ctrl_up
      yield "whereami"
    end

    def on_ctrl_down
      yield "next"
    end

    def on_ctrl_left
      yield "finish"
    end

    def on_ctrl_right
      yield "step"
    end
  end
end
