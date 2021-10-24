require "./history"
require "./expression_editor"
require "./char_reader"
require "./crystal_parser_nest"

module IC::REPLInterface
  class ReplInterface
    @editor = ExpressionEditor.new
    @history = History.new
    @line_number = 1

    private CLOSING_KEYWORD = %w(end \) ] })
    private UNINDENT_KEYWORD = %w(else elsif when in rescue ensure)

    def initialize
      status = :default
      @editor.prompt do |expr_line_number|
        String.build do |io|
          io << "ic(#{Crystal::VERSION}):"
          io << sprintf("%03d", @line_number + expr_line_number).colorize.magenta
          case status
          when :multiline then io << "* "
          else                 io << "> "
          end
        end
      end
    end

    def run(&block : String -> _)
      @editor.prompt_next

      CharReader.read_chars(STDIN) do |char|
        case char
        when :new_line
          if @editor.cursor_on_last_line?
            on_newline { |line| yield line }
          else
            @editor.update { new_line(indent: self.indentation_level) }
          end
        when :up
          has_moved = @editor.move_cursor_up

          if !has_moved
            @history.up(@editor.lines) do |expression|
              @editor.replace(expression)
              @editor.move_cursor_to_end
            end
          end
        when :down
          has_moved = @editor.move_cursor_down

          if !has_moved
            @history.down(@editor.lines) do |expression|
              @editor.replace(expression)
              @editor.move_cursor_to_end_of_first_line
            end
          end
        when :ctrl_up
        when :ctrl_down
        when :left, :ctrl_left
          @editor.move_cursor_left
        when :right, :ctrl_right
          @editor.move_cursor_right
        when :delete
          @editor.update { delete }
        when :back
          @editor.update { back }
        when '\t'
          @editor.update { @editor << ' ' << ' ' }
        when Char
          @editor.update do
            @editor << char
            self.auto_unindent
          end
        end
      end
    end

    private def on_newline(&)
      case @editor.expression
      when "# clear_history", "#clear_history"
        @history.clear
        submit_expr(history: false) do
          puts " => #{"✔".colorize.green}"
        end
        return

      when /^# ?(#{Commands.commands_regex_names})(( [a-z\-]+)*)/
        submit_expr do
          Commands.run_cmd($1?, $2.split(" ", remove_empty: true))
        end
        return

      when .blank?, .starts_with? '#'
        submit_expr(history: false)
        return

        # Replace lines starting by '.' by "__."
        # so ".foo" become "__.foo":
      when /^\.(?!\.)/ # don't match begin-less range ("..x")
        @editor.replace("__#{@editor.expression}".split('\n'))
      end

      if multiline?
        @editor.update { new_line(indent: self.indentation_level) }
      else
        submit_expr do
          yield @editor.expression
        end
      end
    end

    private def multiline?
      Crystal::Parser.parse(@editor.expression)
      false
    rescue e : Crystal::CodeError
      e.unterminated? ? true : false
    end

    private def indentation_level
      parser = Crystal::Parser.new(@editor.expression_before_cursor)
      begin
        parser.parse
      rescue
      end

      parser.type_nest + parser.def_nest + parser.fun_nest + parser.control_nest
    end

    private def formate
      begin
        formated_lines = Crystal.format(@editor.expression).chomp.split('\n')
        @editor.replace(formated_lines)
      rescue
      end
      @editor.move_cursor_to_end
    end

    private def auto_unindent
      last_word = @editor.current_line.split.last?
      case last_word
      when Nil
      when .in? CLOSING_KEYWORD
        @editor.current_line = "  "*self.indentation_level + @editor.current_line.lstrip(' ')
      when .in? UNINDENT_KEYWORD
        indent = {self.indentation_level - 1, 0}.max
        @editor.current_line = "  "*indent + @editor.current_line.lstrip(' ')
      end
    end

    private def submit_expr(*, history = true)
      submit_expr(history: history) { }
    end

    private def submit_expr(*, history = true)
      formate
      @line_number += @editor.lines.size
      @history << @editor.lines if history
      puts

      yield

      @editor.prompt_next
    end
  end
end
