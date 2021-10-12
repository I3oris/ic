require "./history"
require "./expression_editor"
require "./char_reader"

module IC::REPLInterface
  class MultilineInput
    @line_number = 1
    @indent = 0
    @history = History.new

    @multiline : Proc(String, Bool) = ->(expression : String) { false }
    @formate : Proc(String, String) = ->(expression : String) { expression }
    @indentation : Proc(String, Int32) = ->(expression : String) { 0 }
    setter closing_keyword = [] of String
    setter unindent_keyword = [] of String

    def initialize
      @editor = ExpressionEditor.new
    end

    def multiline?(&@multiline : String -> Bool)
    end

    private def multiline?
      @multiline.call(@editor.expression)
    end

    def prompt(&block : Int32, Symbol -> String)
      @editor.prompt do |line_number|
        block.call(@line_number + line_number, :default)
      end
    end

    def formate(&@formate : String -> String)
    end

    def highlight(&block : String -> String)
      @editor.highlight(&block)
    end

    def indentation(&@indentation : String -> Int32)
    end

    def indentation_level
      @indentation.call(@editor.expression_before_cursor)
    end

    private def formate
      begin
        formated_lines = @formate.call(@editor.expression).chomp.split('\n')
        @editor.replace(formated_lines)
      rescue
      end
      @editor.move_cursor_to_end
    end

    private def auto_unindent
      last_word = @editor.current_line.split.last?
      case last_word
      when Nil
      when .in? @closing_keyword
        @editor.current_line = "  "*self.indentation_level + @editor.current_line.lstrip(' ')
      when .in? @unindent_keyword
        indent = {self.indentation_level - 1, 0}.max
        @editor.current_line = "  "*indent + @editor.current_line.lstrip(' ')
      end
    end

    private def submit_expr(*, history = true)
      submit_expr(history: history) { }
    end

    private def submit_expr(*, history = true)
      formate
      @indent = 0
      @line_number += @editor.lines.size
      @history << @editor.lines if history
      puts

      yield

      @editor.prompt_next
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
      when .blank?, /^#.*/
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

    def run(&block : String -> _)
      @editor.prompt_next

      CharReader.read_chars(STDIN) do |char|
        case char
        when :new_line
          if @editor.cursor_on_last_line?
            on_newline(&block)
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
  end
end
