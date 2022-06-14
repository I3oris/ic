require "./history"
require "./expression_editor"
require "./char_reader"
require "./auto_completion_handler"
require "./crystal_parser_nest"
require "colorize"

module IC::ReplInterface
  class ReplInterface
    @editor : ExpressionEditor
    @repl : Crystal::Repl? = nil
    @auto_completion = AutoCompletionHandler.new
    @history = History.new
    getter line_number = 1

    private CLOSING_KEYWORD  = %w(end \) ] })
    private UNINDENT_KEYWORD = %w(else elsif when in rescue ensure)

    delegate :color?, :color=, :lines, :output, :output=, to: @editor
    property repl
    getter auto_completion

    def initialize
      status = :default
      @editor = ExpressionEditor.new do |expr_line_number, _color?|
        String.build do |io|
          io << "ic(#{Crystal::Config.version}):"
          io << sprintf("%03d", @line_number + expr_line_number)
          case status
          when :multiline then io << "* "
          else                 io << "> "
          end
        end
      end
    end

    def initialize(&prompt : Int32, Bool -> String)
      @editor = ExpressionEditor.new(&prompt)
    end

    def run(& : String -> _)
      @editor.prompt_next

      CharReader.read_chars(STDIN) do |read|
        case read
        when :enter
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
              @editor.move_cursor_to_end_of_first_line
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
          @editor.update { back }
        when '\t'
          auto_complete
        when :shift_tab
          auto_complete(shift_tab: true)
        when :escape
          on_escape
        when :insert_new_line
          @editor.update { insert_new_line(indent: self.indentation_level) }
        when :move_cursor_to_begin
          @editor.move_cursor_to_begin
        when :move_cursor_to_end
          @editor.move_cursor_to_end
        when :keyboard_interrupt
          @editor.end_editing { @auto_completion.close(output) }
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

        if !read.in?('\t', :enter, :shift_tab, :escape) && @auto_completion.open?
          @editor.update { @auto_completion.clear(output) }
        end
      end
    end

    # If overriden, can yield an expression to giveback to `run`, see `PryInterface`.
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

    # When `tab` is pressed for auto-completion, we does the followings things:
    # 1) We retrieve the word under the cursor (corresponding to the method name being write)
    # 2) Given the expression before the cursor, the auto-completion handler deduce the
    #    context of auto-completion (which receiver, local vars, etc..)
    # 3) We find entries corresponding to the context + the word_on_cursor. This will give us
    #    the entries (`Array(String)` of method's names), the `receiver_type` name, and the
    #    `replacement` name (`nil` if no entry, full name if only one entry, or partial name that match the most otherwise)
    # 4) Then, during the @editor update, we display theses entries
    # 5) At last, we replace the `word_on_cursor` by the `replacement` word, if any
    # 6) Finally, we move cursor at the end of replaced text.
    private def auto_complete(shift_tab = false)
      line = @editor.current_line

      # 1) Get current word on cursor:
      word_begin, word_end = @editor.word_bound
      word_on_cursor = line[word_begin..word_end]

      if @auto_completion.open?
        if shift_tab
          replacement = @auto_completion.selection_previous
        else
          replacement = @auto_completion.selection_next
        end
      else
        # 2) Set context:
        if repl = @repl
          @auto_completion.set_context(repl)
        end
        # NOTE: if there have no `repl`, in case of `pry`, the context is set somewhere else before.

        expr = @editor.expression_before_cursor(x: word_begin)
        receiver, scope = @auto_completion.parse_receiver_code(expr)

        # 3) Find entries:
        # entries, receiver_name,
        replacement = @auto_completion.find_entries(
          receiver: receiver,
          scope: scope,
          word_on_cursor: word_on_cursor,
        )
      end

      @editor.update do
        # 4) Display completion entries:
        # @auto_completion.clear_previous_display
        @auto_completion.display_entries(output, @editor.expression_height, color?)

        # 5) Replace `word_on_cursor` by the replacement word:
        @editor.current_line = line.sub(word_begin..word_end, replacement) if replacement
      end

      # 6) Move cursor:
      if replacement
        added_size = replacement.size - (@editor.x - word_begin)

        if added_size > 0
          (+added_size).times { @editor.move_cursor_right }
        else
          (-added_size).times { @editor.move_cursor_left }
        end
      end
    end

    private def on_escape
      @editor.update { @auto_completion.close(output) }
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
      begin
        parser.parse
      rescue
      end

      parser.type_nest + parser.def_nest + parser.fun_nest + parser.control_nest
    end

    private def formated
      Crystal.format(@editor.expression).chomp.split('\n') rescue nil
    end

    private def auto_unindent
      current_line = @editor.current_line.rstrip(' ')
      return if @editor.x != current_line.size

      last_word = current_line.split.last?

      case last_word
      when Nil
      when .in? CLOSING_KEYWORD
        @editor.current_line = "  "*self.indentation_level + current_line.lstrip(' ')
      when .in? UNINDENT_KEYWORD
        indent = {self.indentation_level - 1, 0}.max
        @editor.current_line = "  "*indent + current_line.lstrip(' ')
      end
    end

    private def submit_expr(*, history = true)
      submit_expr(history: history) { }
    end

    private def submit_expr(*, history = true, &)
      @editor.end_editing(replacement: formated) do
        @auto_completion.close(output)
      end

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
