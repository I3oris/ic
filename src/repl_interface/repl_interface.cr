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

    property auto_complete : Proc(String?, String, {String, Array(String)}) = ->(receiver : String?, name : String) do
      return {"", [] of String}
    end

    @previous_completion_entries_height : Int32? = nil

    def initialize
      status = :default
      @editor = ExpressionEditor.new(
        prompt: ->(expr_line_number : Int32) do
          String.build do |io|
            io << "ic(#{Crystal::Config.version}):"
            io << sprintf("%03d", @line_number + expr_line_number).colorize.magenta
            case status
            when :multiline then io << "* "
            else                 io << "> "
            end
          end
        end
      )
    end

    def initialize(&prompt : Int32 -> String)
      @editor = ExpressionEditor.new(prompt: prompt)
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
        when :ctrl_up
          @editor.scroll_down
        when :ctrl_down
          @editor.scroll_up
        when :left, :ctrl_left
          @editor.move_cursor_left
        when :right, :ctrl_right
          @editor.move_cursor_right
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

    private def on_enter(&)
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

      if @editor.cursor_on_last_line? && multiline?
        @editor.update { insert_new_line(indent: self.indentation_level) }
      else
        submit_expr do
          yield @editor.expression
        end
      end
    end

    private def on_tab
      line = @editor.current_line

      receiver = nil

      # Get current word on cursor:
      word_begin, word_end = @editor.word_bound
      word_on_cursor = line[word_begin..word_end]

      # Get previous words while they are chained by '.'
      receiver_begin = word_begin
      while line[{receiver_begin - 1, 0}.max]? == '.'
        receiver_begin, _ = @editor.word_bound(x: receiver_begin - 2)
      end
      if receiver_begin != word_begin
        receiver = line[receiver_begin..(word_begin - 2)]?
      end

      # Get auto completion entries:
      context_name, entries = @auto_complete.call(receiver, word_on_cursor)

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
      unless entries.size == 1
        clear_completion_entries

        print context_name.colorize(:blue).underline
        puts ":"

        col_size = entries.max_of &.size + 1

        nb_cols = Term::Size.width // col_size
        nb_rows = {entries.size, Term::Size.height - 1 - @editor.expression_height}.min
        nb_rows = {nb_rows, 0}.max

        array = [] of Array(String)
        entries.each_slice(nb_rows) do |row|
          array << row
        end

        nb_rows.times do |r|
          nb_cols.times do |c|
            entry = array[c]?.try &.[r]?

            if entry && r == nb_rows - 1 && c == nb_cols - 1
              print "...".ljust(col_size)
            else
              entry ||= ""
              print Highlighter.highlight(entry.ljust(col_size))
            end
            # print "|"
          end
          puts
        end

        @previous_completion_entries_height = nb_rows + 1
      end
    end

    private def clear_completion_entries
      if height = @previous_completion_entries_height
        print Term::Cursor.up(height)
        print Term::Cursor.clear_screen_down
        # print Term::Cursor.down(height)
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
