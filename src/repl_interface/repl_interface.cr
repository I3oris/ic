require "./history"
require "./expression_editor"
require "./char_reader"
require "./crystal_parser_nest"
require "colorize"

module IC::ReplInterface
  class ReplInterface
    @editor : ExpressionEditor
    @history = History.new
    @line_number = 1

    private CLOSING_KEYWORD  = %w(end \) ] })
    private UNINDENT_KEYWORD = %w(else elsif when in rescue ensure)

    alias AutoCompleteProc = Proc(String?, String, String?, {String, Array(String)})
    property auto_complete : AutoCompleteProc = ->(receiver : String?, name : String, context_code : String?) do
      return {"", [] of String}
    end

    delegate :color?, :color=, to: @editor

    @previous_completion_entries_height : Int32? = nil

    def initialize
      status = :default
      @editor = ExpressionEditor.new do |expr_line_number, color?|
        String.build do |io|
          io << "ic(#{Crystal::Config.version}):"
          io << sprintf("%03d", @line_number + expr_line_number).colorize(:magenta).toggle(color?)
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
          on_ctrl_up
        when :ctrl_down
          on_ctrl_down
        when :ctrl_left
          on_ctrl_left
        when :ctrl_right
          on_ctrl_right
        when :delete
          @editor.update { delete }
        when :back
          @editor.update { back }
        when '\t'
          on_tab
        when :insert_new_line
          @editor.update { insert_new_line(indent: self.indentation_level) }
        when :move_cursor_to_begin
          @editor.move_cursor_to_begin
        when :move_cursor_to_end
          @editor.move_cursor_to_end
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
      end
    end

    # These macros are here to allow using `yield` when they are overridden on a child class.
    private macro on_ctrl_up
      @editor.scroll_down
    end

    private macro on_ctrl_down
      @editor.scroll_up
    end

    private macro on_ctrl_left
      # TODO: move one word backward
      @editor.move_cursor_left
    end

    private macro on_ctrl_right
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
            puts " => #{"✔".colorize(:green).toggle(color?)}"
          end
          return
        when "# reset", "#reset"
          # TODO reset interpreter
          submit_expr do
            puts " => #{"✔".colorize(:green).toggle(color?)}"
          end
          return
        when .blank?, .starts_with? '#'
          submit_expr(history: false)
          return
        end

        if is_chaining_call?(expr)
          # Replace lines starting by '.' by "__."
          # unless begin-less range ("..x")
          # so ".foo" become "__.foo":
          # @editor.replace("__#{@editor.expression}".split('\n'))
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

    private def on_tab
      line = @editor.current_line

      receiver = nil

      # Get current word on cursor:
      word_begin, word_end = @editor.word_bound
      word_on_cursor = line[word_begin..word_end]

      if is_chaining_call?(@editor.lines[0]?)
        # If expression starts with '.' we want auto-complete from the last result ('__').
        receiver = "__"
      else
        # Get previous words while they are chained by '.'
        receiver_begin = word_begin
        pos = {receiver_begin - 1, 0}.max
        while line[pos]? == '.'
          receiver_begin, _ = @editor.word_bound(x: receiver_begin - 2)

          pos = {receiver_begin - 1, 0}.max
          break if pos == 0
        end

        if receiver_begin != word_begin
          receiver = line[receiver_begin..(word_begin - 2)]?
        end
      end

      # Get auto completion entries:
      context_name, entries = @auto_complete.call(receiver, word_on_cursor, @editor.expression_before_cursor)

      unless entries.empty?
        # Replace word on cursor by the common_root of completion entries:
        replacement = common_root(entries)
        @editor.update do
          print_auto_completion_entries(context_name, entries)

          @editor.current_line = line.sub(word_begin..word_end, replacement)
        end

        # Then move cursor at end of inserted text:
        added_size = replacement.size - (@editor.x - word_begin)

        added_size.times do
          @editor.move_cursor_right
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

    private def common_root(entries)
      return "" if entries.empty?
      return entries[0] if entries.size == 1

      i = 0
      entries_iterator = entries.map &.each_char

      loop do
        char_on_first_entry = entries[0][i]?
        same = entries_iterator.all? do |entry|
          entry.next == char_on_first_entry
        end
        i += 1
        break if !same
      end
      entries[0][...(i - 1)]
    end

    private def print_auto_completion_entries(context_name, entries)
      # clear previous entries if any:
      clear_completion_entries

      # Compute the max number of row in a way to never take more than 3/4 of the screen.
      max_nb_row = (Term::Size.height - @editor.expression_height)*3//4 - 1
      return if max_nb_row <= 1
      return if entries.size <= 1

      # Print context type name:
      print context_name.colorize(:blue).underline.toggle(color?)
      puts ":"

      nb_rows = compute_nb_row(entries, max_nb_row)

      columns = entries.in_groups_of(nb_rows, "")
      column_widths = columns.map &.max_of &.size.+(2)

      nb_rows.times do |r|
        width = 0
        columns.each_with_index do |col, c|
          entry = col[r]
          col_width = column_widths[c]

          # As we doesn't known the nb of column to display, stop when column overflow the term width:
          width += col_width
          break if width > Term::Size.width

          # Display `...` on the last column and row:
          if r == nb_rows - 1 && (next_col_width = column_widths[c + 1]?) && width + next_col_width > Term::Size.width
            entry = "..."
          end

          # Display entry:
          print Highlighter.highlight(entry.ljust(col_width))
        end
        puts
      end

      @previous_completion_entries_height = nb_rows + 1
    end

    # Computes the min number of rows required to display entries:
    # * if all entries cannot fit in `max_nb_row` rows, returns `max_nb_row`,
    # * if there are less than 10 entries, returns `entries.size` because in this case, it's more convenient to display them in one column.
    private def compute_nb_row(entries, max_nb_row)
      if entries.size > 10
        # test possible nb rows: (1 to max_nb_row)
        1.to max_nb_row do |r|
          width = 0
          # Sum the width of each given column:
          entries.each_slice(r, reuse: true) do |col|
            width += col.max_of &.size + 2
          end

          # If width fit width terminal, we found min row required:
          return r if width < Term::Size.width
        end
      end

      {entries.size, max_nb_row}.min
    end

    private def clear_completion_entries
      print Term::Cursor.clear_line_after

      if height = @previous_completion_entries_height
        print Term::Cursor.up(height)
        print Term::Cursor.clear_screen_down

        @previous_completion_entries_height = nil
      end
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
      @editor.end_editing(replace: formated) do
        clear_completion_entries
      end

      @line_number += @editor.lines.size
      @history << @editor.lines if history

      yield

      @editor.prompt_next
    end
  end
end
