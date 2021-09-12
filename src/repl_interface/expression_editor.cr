require "./term_cursor"
require "./term_size"

module IC::REPLInterface
  alias Lines = Array(String)

  class ExpressionEditor
    getter lines : Lines = [""]
    getter expression : String? { lines.join('\n') }

    private struct Cursor
      property x = 0, y = 0

      def abs_move(x, y)
        move(x - @x, y - @y)
      end

      def move(x, y)
        @x += x
        @y += y
      end

      def reset
        @x = 0
        @y = 0
      end
    end

    @cursor = Cursor.new
    @highlight : Proc(String, String) = ->(expression : String) { expression }
    @prompt : Proc(Int32, String) = ->(line_number : Int32) { sprintf("%03d> ", line_number) }
    @prompt_size = 5

    # Prompt size must stay constant.
    def prompt(&@prompt : Int32 -> String)
      @prompt_size = @prompt.call(0).gsub(/\e\[.*?m/, "").size # uncolorize
    end

    def highlight(&block : String -> String)
      @highlight = block
    end

    def current_line
      @lines[@cursor.y]
    end

    def previous_line?
      if @cursor.y > 0
        @lines[@cursor.y - 1]
      end
    end

    def next_line?
      @lines[@cursor.y + 1]?
    end

    def cursor_on_last_line?
      (@cursor.y == @lines.size - 1)
    end

    def expression_before_cursor
      @lines[...@cursor.y].join('\n') + '\n' + current_line[..@cursor.x]
    end

    def previous_line=(line)
      @lines[@cursor.y - 1] = line
      @expression = nil
    end

    def current_line=(line)
      @lines[@cursor.y] = line
      @expression = nil
    end

    def next_line=(line)
      @lines[@cursor.y + 1] = line
      @expression = nil
    end

    def delete_line(y)
      @lines.delete_at(y)
      @expression = nil
    end

    def <<(char : Char)
      if @cursor.x >= current_line.size
        self.current_line = current_line + char
      else
        self.current_line = current_line.insert(@cursor.x, char)
      end

      @cursor.move(x: +1, y: 0)
      self
    end

    def new_line(indent)
      case @cursor.x
      when current_line.size
        @lines.insert(@cursor.y + 1, "  "*indent)
      when .< current_line.size
        @lines.insert(@cursor.y + 1, "  "*indent + current_line[@cursor.x..])
        self.current_line = current_line[...@cursor.x]
      end

      @expression = nil
      @cursor.abs_move(x: indent*2, y: @cursor.y + 1)
    end

    def delete
      case @cursor.x
      when current_line.size
        if next_line = next_line?
          self.current_line = current_line + next_line

          delete_line(@cursor.y + 1)
        end
      when .< current_line.size
        self.current_line = current_line.delete_at(@cursor.x)
      end
    end

    def back
      case @cursor.x
      when 0
        if prev_line = previous_line?
          self.previous_line = prev_line + current_line

          @cursor.move(x: prev_line.size, y: -1)
          delete_line(@cursor.y + 1)
        end
      when .> 0
        self.current_line = current_line.delete_at(@cursor.x - 1)
        @cursor.move(x: -1, y: 0)
      end
    end

    def move_cursor_left
      case @cursor.x
      when 0
        # Wrap the @cursor at the end of the previous line:
        #
        # `|`: @cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo
        # oooong_name*
        # prompt> | bar
        # prompt> end
        # ```
        if prev_line = previous_line?
          # Wrap real cursor:
          end_of_previous_line = ((@prompt_size + prev_line.size) % Term::Size.width) - @prompt_size
          print Term::Cursor.move(x: end_of_previous_line, y: +1)

          # Wrap @cursor:
          @cursor.move(x: prev_line.size, y: -1)
        end
      when .> 0
        # Move the cursor left, wrap the real cursor if needed:
        #
        # `|`: @cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo*
        # |ooong_name
        # prompt>   bar
        # prompt> end
        # ```
        if (@prompt_size + @cursor.x) % Term::Size.width == 0
          print Term::Cursor.move(x: Term::Size.width + 1, y: +1)
        else
          print Term::Cursor.move(x: -1, y: 0)
        end

        # move @cursor left
        @cursor.move(x: -1, y: 0)
      end
    end

    def move_cursor_right
      case @cursor.x
      when current_line.size
        # Wrap the @cursor at the beginning of the next line:
        #
        # `|`: @cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo
        # oooong_name|
        # prompt> * bar
        # prompt> end
        # ```
        if next_line?
          # Wrap real cursor:
          end_of_current_line = (@prompt_size + current_line.size) % Term::Size.width
          print Term::Cursor.move(x: -end_of_current_line + @prompt_size, y: -1)

          # Wrap @cursor:
          @cursor.move(x: -current_line.size, y: +1)
        end
      when .< current_line.size
        # Move the cursor right, wrap the real cursor if needed:
        #
        # `|`: @cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo|
        # *ooong_name
        # prompt>   bar
        # prompt> end
        # ```
        if (@prompt_size + @cursor.x) % Term::Size.width == (Term::Size.width - 1)
          print Term::Cursor.move(x: -(Term::Size.width + 1), y: -1)
        else
          print Term::Cursor.move(x: +1, y: 0)
        end

        # move @cursor right
        @cursor.move(x: +1, y: 0)
      end
    end

    # TODO: handle real cursor wrapping
    def move_cursor_up
      # if prev_line = previous_line?
      #   x = @cursor.x.clamp(0, prev_line.size)
      #   @cursor.abs_move(x: x, y: @cursor.y - 1)
      #   true
      # end
    end

    # TODO: handle real cursor wrapping:
    def move_cursor_down
      # if next_line = next_line?
      #   x = @cursor.x.clamp(0, next_line.size)
      #   @cursor.abs_move(x: x, y: @cursor.y + 1)
      #   true
      # end
    end

    def move_cursor_to_begin
      until {@cursor.x, @cursor.y} == {0, 0}
        move_cursor_left # TODO: use move_cursor_up instead
        raise "Bug: moving cursor to begin never hit the beginning" if @cursor.x < 0 || @cursor.y < 0
      end
    end

    def move_cursor_to_end
      y_end = @lines.size - 1
      x_end = @lines[y_end].size

      until {@cursor.x, @cursor.y} == {x_end, y_end}
        move_cursor_right # TODO: use move_cursor_down instead

        raise "Bug: moving cursor to end never hit the end" if @cursor.y > y_end
      end
    end

    # TODO: handle real cursor wrapping:
    def move_cursor_to_end_of_first_line
      @cursor.abs_move @lines[0].size, 0
    end

    # Clean the screen, `@cursor` stay unchanged but real cursor is set to the beginning of expression
    # Handles the lines wrapping
    #
    # before:
    #
    # ```
    # prompt> def very_looo
    # oooong_name
    # prompt>   bar|
    # prompt> end
    # ```
    #
    # @cursor = {x: 5, y: 1}
    # real cursor: x: 13, y: ?+2
    #
    # after:
    #
    # ```
    # |
    # ```
    #
    # @cursor = {x: 5, y: 1}
    # real cursor: x: 0, y: ?+0
    private def clear_screen # private
      x_save, y_save = @cursor.x, @cursor.y
      move_cursor_to_begin
      @cursor.x, @cursor.y = x_save, y_save

      print Term::Cursor.column(1)
      print Term::Cursor.clear_screen_down
    end

    # Displays the colorized expression with a prompt, real cursor is so at the end of the expression
    private def print_expression
      colorized_lines = @highlight.call(self.expression).split('\n')

      colorized_lines.each_with_index do |line, i|
        print @prompt.call(i)
        print line

        puts if (@prompt_size + @lines[i].size) % Term::Size.width == 0

        puts unless i == colorized_lines.size - 1
      end
    end

    # if real cursor is at end of lines, set the real cursor at the @cursor position
    # private
    private def replace_real_cursor_from_end
      x_save, y_save = @cursor.x, @cursor.y
      @cursor.y = @lines.size - 1
      @cursor.x = @lines[@cursor.y].size
      loop do
        break if @cursor.x == x_save && @cursor.y == y_save
        if @cursor.x < 0 || @cursor.y < 0
          raise "Bug: replacing real cursor never hit the @cursor"
        end
        move_cursor_left
      end
    end

    @[Deprecated]
    private def size_on_screen(line)
      line_size = (@prompt_size + line.size) # + 1)

      line_size_on_screen = line_size // Term::Size.width
      {x: line_size % Term::Size.width, y: line_size_on_screen + 1}
    end

    def update(&)
      clear_screen

      with self yield

      @expression = nil
      print_expression

      y = @cursor.y.clamp(0, @lines.size - 1)
      x = @cursor.x.clamp(0, @lines[y].size)
      @cursor.abs_move(x, y)
      replace_real_cursor_from_end
    end

    def replace(lines : Lines)
      update { @lines = lines }
    end

    def prompt_next
      @lines = [""]
      @expression = nil
      @cursor.reset
      print @prompt.call(0)
    end
  end
end
