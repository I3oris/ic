require "./term_cursor"
require "./term_size"

module IC::REPLInterface
  class ExpressionEditor
    getter lines : Array(String) = [""]
    getter expression : String? { lines.join('\n') }

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

    # Tracks the cursor position relatively to the expressions lines, (y=0 corresponds to the first line and x=0 the first char)
    # This position is independent of text wrapping so its position will not match to real cursor on screen.
    #
    # `|` : cursor position
    #
    # ```
    # prompt> def very_looo
    # ooo|ng_name            <= wrapping
    # prompt>   bar
    # prompt> end
    # ```
    # For example here the cursor position is x=16, y=0, but real cursor is at x=3,y=1 from the beginning of expression.
    @x = 0
    @y = 0

    def move_cursor(x, y)
      @x += x
      @y += y
    end

    def move_real_cursor(x, y)
      print Term::Cursor.move(x, -y)
    end

    def move_abs_cursor(@x, @y)
    end

    def reset_cursor
      @x = @y = 0
    end

    def current_line
      @lines[@y]
    end

    def previous_line?
      if @y > 0
        @lines[@y - 1]
      end
    end

    def next_line?
      @lines[@y + 1]?
    end

    def cursor_on_last_line?
      (@y == @lines.size - 1)
    end

    def expression_before_cursor
      @lines[...@y].join('\n') + '\n' + current_line[..@x]
    end

    # Following functions modify the expression, so it's generally better to call them inside
    # an `update` block to see the change in the screen : #

    def previous_line=(line)
      @lines[@y - 1] = line
      @expression = nil
    end

    def current_line=(line)
      @lines[@y] = line
      @expression = nil
    end

    def next_line=(line)
      @lines[@y + 1] = line
      @expression = nil
    end

    def delete_line(y)
      @lines.delete_at(y)
      @expression = nil
    end

    def <<(char : Char)
      if @x >= current_line.size
        self.current_line = current_line + char
      else
        self.current_line = current_line.insert(@x, char)
      end

      move_cursor(x: +1, y: 0)
      self
    end

    def new_line(indent)
      case @x
      when current_line.size
        @lines.insert(@y + 1, "  "*indent)
      when .< current_line.size
        @lines.insert(@y + 1, "  "*indent + current_line[@x..])
        self.current_line = current_line[...@x]
      end

      @expression = nil
      move_abs_cursor(x: indent*2, y: @y + 1)
    end

    def delete
      case @x
      when current_line.size
        if next_line = next_line?
          self.current_line = current_line + next_line

          delete_line(@y + 1)
        end
      when .< current_line.size
        self.current_line = current_line.delete_at(@x)
      end
    end

    def back
      case @x
      when 0
        if prev_line = previous_line?
          self.previous_line = prev_line + current_line

          move_cursor(x: prev_line.size, y: -1)
          delete_line(@y + 1)
        end
      when .> 0
        self.current_line = current_line.delete_at(@x - 1)
        move_cursor(x: -1, y: 0)
      end
    end

    # End modifying functions. #

    # Give the size of the last part of the line when it's wrapped
    #
    # prompt> def very_looo
    # ooooooooong              <= last part
    # prompt>   bar
    # prompt> end
    #
    # e.g. here "ooong_name".size = 10
    private def remainding_size(line_size)
      (@prompt_size + line_size) % Term::Size.width
    end

    def move_cursor_left
      case @x
      when 0
        # Wrap the cursor at the end of the previous line:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo
        # ooooooooong*
        # prompt> | bar
        # prompt> end
        # ```
        if prev_line = previous_line?
          # Wrap real cursor:
          size_of_last_part = remainding_size(prev_line.size)
          move_real_cursor(x: -@prompt_size + size_of_last_part, y: -1)

          # Wrap cursor:
          move_cursor(x: prev_line.size, y: -1)
        end
      when .> 0
        # Move the cursor left, wrap the real cursor if needed:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo*
        # |oooooooong
        # prompt>   bar
        # prompt> end
        # ```
        if remainding_size(@x) == 0
          move_real_cursor(x: Term::Size.width + 1, y: -1)
        else
          move_real_cursor(x: -1, y: 0)
        end
        move_cursor(x: -1, y: 0)
      end
    end

    def move_cursor_right
      case @x
      when current_line.size
        # Wrap the cursor at the beginning of the next line:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo
        # ooooooooong|
        # prompt> * bar
        # prompt> end
        # ```
        if next_line?
          # Wrap real cursor:
          size_of_last_part = remainding_size(current_line.size)
          move_real_cursor(x: -size_of_last_part + @prompt_size, y: +1)

          # Wrap cursor:
          move_cursor(x: -current_line.size, y: +1)
        end
      when .< current_line.size
        # Move the cursor right, wrap the real cursor if needed:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt> def very_looo|
        # *oooooooong
        # prompt>   bar
        # prompt> end
        # ```
        if remainding_size(@x) == (Term::Size.width - 1)
          move_real_cursor(x: -Term::Size.width, y: +1)
        else
          move_real_cursor(x: +1, y: 0)
        end

        # move cursor right
        move_cursor(x: +1, y: 0)
      end
    end

    def move_cursor_up
      if (@prompt_size + @x) >= Term::Size.width
        if @x >= Term::Size.width
          # Here, we are:
          # ```
          # prompt> def *very_loo
          # oooooooooooo|oooooooo
          # ooooooooong
          # prompt>   bar
          # prompt> end
          # ```
          # So we need only to move real cursor up
          # and move back @x by term-width.
          #
          move_real_cursor(x: 0, y: -1)
          move_cursor(x: -Term::Size.width, y: 0)
        else
          # Here, we are:
          # ```
          # prompt> *def very_loo
          # ooo|ooooooooooooooooo
          # ooooooooong
          # prompt>   bar
          # prompt> end
          # ```
          #
          move_real_cursor(x: Term::Size.width - @x, y: -1)
          move_cursor(x: 0 - @x, y: 0)
        end

        true
      elsif prev_line = previous_line?
        # Here, there are a previous line in witch we can move up, we want to
        # move on the last part of the previous line
        size_of_last_part = remainding_size(prev_line.size)

        if size_of_last_part < @prompt_size + @x
          # ```
          # prompt> def very_loo
          # oooooooooooooooooooo
          # ong*                  <= last part
          # prompt>   ba|aar
          # prompt> end
          # ```
          move_real_cursor(x: -@x - @prompt_size + size_of_last_part, y: -1)
          move_abs_cursor(x: prev_line.size, y: @y - 1)
        else
          # ```
          # prompt> def very_loo
          # oooooooooooooooooooo
          # oooooooooooo*oong    <= last part
          # prompt>   ba|aar
          # prompt> end
          # ```
          move_real_cursor(x: 0, y: -1)
          x = prev_line.size - size_of_last_part + @prompt_size + @x
          move_abs_cursor(x: x, y: @y - 1)
        end
        true
      else
        false
      end
    end

    # TODO: handle real cursor wrapping:
    def move_cursor_down
      # many lines:
      size_of_last_part = remainding_size(current_line.size)
      real_x = remainding_size(@x)

      remainding = current_line.size - @x

      if remainding > size_of_last_part
        # on middle
        if remainding > Term::Size.width
          # Here, there are enough remainding to just move down
          # ```
          # prompt>  def ve|ry_loo
          # ooooooooooooooo*oooooo
          # ong
          # prompt>   bar
          # prompt> end
          # ```
          #
          move_real_cursor(x: 0, y: +1)
          move_cursor(x: Term::Size.width, y: 0)
        else
          # Here, we goes to end of current line:
          # ```
          # prompt>  def very_loo
          # ooooooooooooooo|ooooo
          # ong*
          # prompt>   bar
          # prompt> end
          # ```
          move_real_cursor(x: -real_x + size_of_last_part, y: +1)
          move_abs_cursor(x: current_line.size, y: @y)
        end
        true
      elsif next_line = next_line?
        case real_x
        when .< @prompt_size
          # Here, we are behind the prompt so we want goes to the begining of the next line:
          # ```
          # prompt>  def very_loo
          # ooooooooooooooooooooo
          # ong|
          # prompt> * bar
          # prompt> end
          # ```
          move_real_cursor(x: -real_x + @prompt_size, y: +1)
          move_abs_cursor(x: 0, y: @y + 1)
        when .< @prompt_size + next_line.size
          # Here, we can just move down on the next line:
          # ```
          # prompt>  def very_loo
          # ooooooooooooooooooooo
          # ooooooooong|
          # prompt>   b*ar
          # prompt> end
          # ```
          move_real_cursor(x: 0, y: +1)
          move_abs_cursor(x: real_x - @prompt_size, y: @y + 1)
        else
          # Finally, here, want to move at end of the next line:
          # ```
          # prompt>  def very_loo
          # ooooooooooooooooooooo
          # ooooooooooooooong|
          # prompt>   bar*
          # prompt> end
          # ```
          x = real_x - (@prompt_size + next_line.size)
          move_real_cursor(x: -x, y: +1)
          move_abs_cursor(x: next_line.size, y: @y + 1)
        end
        true
      else
        false
      end
    end

    def move_cursor_to_begin
      until {@x, @y} == {0, 0}
        move_cursor_left # TODO: use move_cursor_up instead
        raise "Bug: moving cursor to begin never hit the beginning" if @x < 0 || @y < 0
      end
    end

    def move_cursor_to_end
      y_end = @lines.size - 1
      x_end = @lines[y_end].size

      until {@x, @y} == {x_end, y_end}
        move_cursor_right # TODO: use move_cursor_down instead

        raise "Bug: moving cursor to end never hit the end" if @y > y_end
      end
    end

    # TODO: handle real cursor wrapping:
    def move_cursor_to_end_of_first_line
      move_abs_cursor(x: @lines[0].size, y: 0)
    end

    # Clean the screen, cursor stay unchanged but real cursor is set to the beginning of expression
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
    # @x: 5, @y: 1
    # real cursor: x: 13, y: ?+2
    #
    # after:
    #
    # ```
    # |
    # ```
    #
    # @x: 5, @y: 1
    # real cursor: x: 0, y: ?+0
    private def clear_screen
      x_save, y_save = @x, @y
      move_cursor_to_begin
      @x, @y = x_save, y_save

      print Term::Cursor.column(1)
      print Term::Cursor.clear_screen_down
    end

    # Displays the colorized expression with a prompt, real cursor is so at the end of the expression
    private def print_expression
      colorized_lines = @highlight.call(self.expression).split('\n')

      colorized_lines.each_with_index do |line, i|
        print @prompt.call(i)
        print line

        puts if remainding_size(@lines[i].size) == 0

        puts unless i == colorized_lines.size - 1
      end
    end

    # if real cursor is at end of the expression, set the real cursor at the cursor position (`@x`, `@y`)
    private def replace_real_cursor_from_end
      x_save, y_save = @x, @y
      @y = @lines.size - 1
      @x = @lines[@y].size
      loop do
        break if @x == x_save && @y == y_save
        if @x < 0 || @y < 0
          raise "Bug: replacing real cursor never hit the cursor"
        end
        move_cursor_left # TODO use move_cursor down
      end
    end

    # Clear the screen, yields for modifications, and displays the new expression.
    # cursor is adjusted to not overflow if the new expression is smaller.
    def update(&)
      clear_screen

      with self yield

      @expression = nil
      print_expression

      y = @y.clamp(0, @lines.size - 1)
      x = @x.clamp(0, @lines[y].size)
      move_abs_cursor(x, y)
      replace_real_cursor_from_end
    end

    def replace(lines : Array(String))
      update { @lines = lines.dup }
    end

    def prompt_next
      @lines = [""]
      @expression = nil
      reset_cursor
      print @prompt.call(0)
    end
  end
end
