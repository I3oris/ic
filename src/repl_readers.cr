require "reply"
require "./crystal_completer"
require "./crystal_parser_nest"
require "./highlighter"

module Crystal
  class ReplReader
    @highlighter = IC::Highlighter.new
    @crystal_completer = IC::CrystalCompleter.new

    # Adding history max size
    def initialize(@repl = nil)
      super()

      # `"`, `:`, `'`, are not a delimiter because symbols and strings are treated as one word.
      # '=', !', '?' are not a delimiter because they could make part of method name.
      self.word_delimiters = {{" \n\t+-*/,;@&%<>^\\[](){}|.~".chars}}

      if size = ENV["IC_HISTORY_SIZE"]?.try &.to_i?
        self.history.max_size = size
      end
    end

    # Using custom highlighter
    def highlight(expression : String) : String
      @highlighter.highlight(expression)
    end

    # Adding control nest and case nest
    def indentation_level(expression_before_cursor : String) : Int32?
      parser = new_parser(expression_before_cursor)
      parser.parse rescue nil

      parser.type_nest + parser.def_nest + parser.fun_nest + parser.control_nest + parser.case_nest
    end

    # Adding special treatment for `in` and `when`.
    def reindent_line(line : String)
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

    # Adding save in history
    def history_file
      if file = ENV["IC_HISTORY_FILE"]?
        return nil if file.empty?
        file
      else
        ::Path.home / ".ic_history"
      end
    end

    # Adding #clear_history and #reset commands
    def read_loop(& : String -> _)
      super do |expr|
        case expr
        when "# clear_history", "#clear_history"
          self.clear_history
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

    # Changing prompt
    def prompt(io : IO, line_number : Int32, color? : Bool) : Nil
      io << "ic(#{Crystal::Config.version}):"
      io << sprintf("%03d", line_number)
      io << "> "
    end

    # Adding auto-completion
    def auto_complete(name_filter : String, expression : String)
      return "", [] of String unless repl = @repl
      return "", [] of String unless repl.prelude_complete? # Prevent to trigger auto-completion while running the prelude.

      # Set auto-completion context from repl, allow auto-completion to take account of previously defined types, methods and local vars.
      @crystal_completer.set_context(repl)
      @crystal_completer.complete_on(name_filter, expression)
    end

    def auto_completion_display_title(io : IO, title : String)
      io << @highlighter.highlight(title) << ":"
    end

    private def print_status(status)
      icon = status ? "✔".colorize(:green) : "×".colorize(:red)
      self.output.puts " => #{icon}"
    end

    private def in_a_case?
      parser = new_parser(@editor.expression_before_cursor)
      parser.parse rescue nil

      parser.case_nest > 0
    end

    def reset
      super
      @repl.try &.reset
    end
  end

  class PryReader < ReplReader
    def prompt(io, line_number, color?)
      io << "ic(#{Crystal::Config.version}):"
      io << "pry".colorize(:magenta).toggle(color?)
      io << "> "
    end

    # Disable persistent history for pry
    def history_file
      nil
    end

    def set_context(local_vars, program, main_visitor, special_commands)
      @crystal_completer.set_context(local_vars, program, main_visitor, special_commands)
    end

    # Adding auto-completion
    def auto_complete(name_filter, expression)
      @crystal_completer.complete_on(name_filter, expression)
    end

    # Keep old behavior
    def on_ctrl_up
      yield "whereami"
    end
  end
end
