require "./history"
require "./expression_editor"
require "./char_reader"
require "./auto_completion_handler"
require "../crystal_parser_nest"
require "colorize"

module IC::ReplInterface
  class ReplInterface
    @editor : ExpressionEditor
    @history = History.new
    property repl : Crystal::Repl? = nil
    getter auto_completion = AutoCompletionHandler.new
    getter line_number = 1

    private CLOSING_KEYWORD  = %w(end \) ] })
    private UNINDENT_KEYWORD = %w(else elsif when in rescue ensure)

    delegate :color?, :color=, :lines, :output, :output=, to: @editor

    def initialize(&prompt : Int32, Bool -> String)
      @editor = ExpressionEditor.new(&prompt)
      @editor.set_header do |io, previous_height|
        @auto_completion.display_entries(io, color?, max_height: {10, Term::Size.height - 1}.min, min_height: previous_height)
      end
    end

    def initialize
      initialize do |expr_line_number, _color?|
        String.build do |io|
          io << "ic(#{Crystal::Config.version}):"
          io << sprintf("%03d", @line_number + expr_line_number)
          io << "> "
        end
      end
    end

    def run(& : String -> _)
      @editor.prompt_next

      CharReader.read_chars(STDIN) do |read|
        case read
        when :enter
          @auto_completion.close
          on_enter { |line| yield line }
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
              @editor.move_cursor_to_end_of_line(y: 0)
            end
          end
        when :left
          @editor.move_cursor_left
        when :right
          @editor.move_cursor_right
        when :ctrl_up
          on_ctrl_up { |line| yield line }
        when :ctrl_down
          on_ctrl_down { |line| yield line }
        when :ctrl_left
          on_ctrl_left { |line| yield line }
        when :ctrl_right
          on_ctrl_right { |line| yield line }
        when :delete
          @editor.update { delete }
        when :back
          auto_complete_remove_char if @auto_completion.open?
          @editor.update { back }
        when :tab
          auto_complete
        when :shift_tab
          auto_complete(shift_tab: true)
        when :escape
          @auto_completion.close
          @editor.update
        when :insert_new_line
          @auto_completion.close
          @editor.update { insert_new_line(indent: self.indentation_level) }
        when :move_cursor_to_begin
          @editor.move_cursor_to_begin
        when :move_cursor_to_end
          @editor.move_cursor_to_end
        when :keyboard_interrupt
          @auto_completion.close
          @editor.end_editing
          output.puts "^C"
          @history.set_to_last
          @editor.prompt_next
          next
        when Char
          @editor.update do
            @editor << read
            self.auto_unindent
          end
        when String
          @editor.update do
            @editor << read
          end
        end

        if !read.in?(:tab, :enter, :insert_new_line, :shift_tab, :escape, :back) && @auto_completion.open?
          auto_complete_insert_char(read)
          @editor.update
        end
      end
    end

    # If overridden, can yield an expression to giveback to `run`, see `PryInterface`.
    private def on_ctrl_up(& : String ->)
      @editor.scroll_down
    end

    private def on_ctrl_down(& : String ->)
      @editor.scroll_up
    end

    private def on_ctrl_left(& : String ->)
      # TODO: move one word backward
      @editor.move_cursor_left
    end

    private def on_ctrl_right(& : String ->)
      # TODO: move one word forward
      @editor.move_cursor_right
    end

    private def on_enter(&)
      if @editor.lines.size == 1
        expr = @editor.expression

        case expr
        when "# clear_history", "#clear_history"
          @history.clear
          submit_expr(history: false) do
            output.puts " => #{"✔".colorize(:green).toggle(color?)}"
          end
          return
        when "# reset", "#reset"
          submit_expr do
            status = self.reset rescue false
            icon = status ? "✔".colorize(:green) : "×".colorize(:red)
            output.puts " => #{icon.toggle(color?)}"
          end
          return
        when .blank?
          submit_expr(history: false)
          return
        end

        if is_chaining_call?(expr)
          # Replace lines starting by '.' by "__."
          # unless begin-less range ("..x")
          # so ".foo" become "__.foo":
          @editor.current_line = "__#{@editor.current_line}"
          @editor.move_cursor_to_end
        end
      end

      if @editor.cursor_on_last_line? && multiline?
        @editor.update { insert_new_line(indent: self.indentation_level) }
      else
        submit_expr do
          yield @editor.expression
        end
      end
    end

    private def is_chaining_call?(expr)
      expr && expr.starts_with?('.') && !expr.starts_with?("..")
    end

    private def auto_complete(shift_tab = false)
      repl = @repl
      return if repl && !repl.prelude_complete? # Prevent to trigger auto-completion while running the prelude.

      line = @editor.current_line

      # Retrieve the word under the cursor (corresponding to the method name being write)
      word_begin, word_end = @editor.word_bound
      word_on_cursor = line[word_begin..word_end]

      if @auto_completion.open?
        if shift_tab
          replacement = @auto_completion.selection_previous
        else
          replacement = @auto_completion.selection_next
        end
      else
        # Set auto-completion context from repl, allow auto-completion to take account of previously defined types, methods and local vars.
        @auto_completion.set_context(repl) if repl

        # Get hole expression before cursor, allow auto-completion to deduce the receiver type
        expr = @editor.expression_before_cursor(x: word_begin)

        # Compute auto-completion, return `replacement` (`nil` if no entry, full name if only one entry, or the begin match of entries otherwise)
        replacement = @auto_completion.complete_on(word_on_cursor, expr)

        @auto_completion.open if replacement
      end

      @editor.update do
        # Replace `word_on_cursor` by the replacement word:
        @editor.current_line = line.sub(word_begin..word_end, replacement) if replacement
      end

      # Move cursor:
      if replacement
        @editor.move_cursor_to(x: word_begin + replacement.size, y: @editor.y)
      end
    end

    private def auto_complete_insert_char(read)
      if read.is_a? Char && @editor.word_char?(@editor.x - 1)
        line = @editor.current_line

        # Retrieve the word under the cursor (corresponding to the method name being write)
        word_begin, word_end = @editor.word_bound
        word_on_cursor = line[word_begin..word_end]

        @auto_completion.name_filter = word_on_cursor
      elsif @editor.expression_scrolled? || read.is_a?(String)
        @auto_completion.close
      else
        @auto_completion.clear
      end
    end

    private def auto_complete_remove_char
      if @editor.word_char?(@editor.x - 1)
        line = @editor.current_line

        word_begin, word_end = @editor.word_bound
        word_on_cursor = line[word_begin..(word_end - 1)]
        @auto_completion.name_filter = word_on_cursor
      else
        @auto_completion.clear
      end
    end

    private def create_parser(code)
      if repl = @repl
        repl.create_parser(code)
      else
        Crystal::Parser.new(code)
      end
    end

    private def multiline?
      create_parser(@editor.expression).parse
      false
    rescue e : Crystal::CodeError
      e.unterminated? ? true : false
    end

    private def indentation_level
      parser = create_parser(@editor.expression_before_cursor)
      parser.parse rescue nil

      parser.type_nest + parser.def_nest + parser.fun_nest + parser.control_nest + parser.case_nest
    end

    private def indentation_level_if_in_a_case
      parser = create_parser(@editor.expression_before_cursor)
      parser.parse rescue nil

      if parser.case_nest > 0
        parser.type_nest + parser.def_nest + parser.fun_nest + parser.control_nest + parser.case_nest
      end
    end

    private def formated
      Crystal.format(@editor.expression).chomp.split('\n') rescue nil
    end

    private def auto_unindent
      current_line = @editor.current_line.rstrip(' ')
      return if @editor.x != current_line.size

      keyword = current_line.lstrip(' ')

      case keyword
      when Nil
      when .in? CLOSING_KEYWORD
        @editor.current_line = "  "*self.indentation_level + keyword
      when "in", "when"
        if indent_level = self.indentation_level_if_in_a_case
          indent = {indent_level - 1, 0}.max
          @editor.current_line = "  "*indent + keyword
        end
      when .in? UNINDENT_KEYWORD
        indent = {self.indentation_level - 1, 0}.max
        @editor.current_line = "  "*indent + keyword
      end
    end

    private def submit_expr(*, history = true)
      submit_expr(history: history) { }
    end

    private def submit_expr(*, history = true, &)
      @editor.end_editing(replacement: formated)

      @line_number += @editor.lines.size
      @history << @editor.lines if history

      yield

      @editor.prompt_next
    end

    def reset
      if repl = @repl
        repl.reset
        @line_number = 1
      end
    end
  end
end
