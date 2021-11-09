require "./term_cursor"
require "./term_size"
require "../highlighter"

module IC::ReplInterface
  # ExpressionEditor allows to edit and display an expression:
  #
  # Usage example:
  # ```
  # # new editor:
  # @editor = ExpressionEditor.new(
  #   prompt: ->(expr_line_number : Int32) { "prompt> " }
  # )
  #
  # # edit some code:
  # @editor.update do
  #   @editor << %(puts "World")
  #
  #   insert_new_line(indent: 1)
  #   @editor << %(puts "!")
  # end
  #
  # # move cursor:
  # @editor.move_cursor_up
  # 4.times { @editor.move_cursor_left }
  #
  # # edit:
  # @editor.update do
  #   @editor << "Hello "
  # end
  #
  # @editor.end_editing
  #
  # @editor.expression # => %(puts "Hello World"\n  puts "!")
  # puts "=> ok"
  #
  # # clear and restart edition:
  # @editor.prompt_next
  # ```
  #
  # The above has displayed:
  #
  # prompt> puts "Hello World"
  # prompt>   puts "!"
  # => ok
  # prompt>
  #
  class ExpressionEditor
    getter lines : Array(String) = [""]
    getter expression : String? { lines.join('\n') }

    @highlighter = Highlighter.new
    @prompt : Int32 -> String
    @prompt_size : Int32

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

    @scroll_offset = 0

    # Prompt size must stay constant.
    def initialize(@prompt : Int32 -> String)
      @prompt_size = @prompt.call(0).gsub(/\e\[.*?m/, "").size # uncolorized size
    end

    private def move_cursor(x, y)
      @x += x
      @y += y
    end

    private def move_real_cursor(x, y)
      print Term::Cursor.move(x, -y)
    end

    private def move_abs_cursor(@x, @y)
    end

    private def reset_cursor
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

    # Following functions modify the expression, they should be called inside
    # an `update` block to see the changes in the screen : #

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
      return insert_new_line(0) if char.in? '\n', '\r'

      if @x >= current_line.size
        self.current_line = current_line + char
      else
        self.current_line = current_line.insert(@x, char)
      end

      move_cursor(x: +1, y: 0)
      self
    end

    def <<(str : String)
      str.each_char do |ch|
        self << ch
      end
    end

    def insert_new_line(indent)
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
    # e.g. here "ooooooooong".size = 10
    private def remainding_size(line_size)
      (@prompt_size + line_size) % Term::Size.width
    end

    # Returns the part number *p* of this line:
    private def part(line, p)
      first_part_size = (Term::Size.width - @prompt_size)
      if p == 0
        line[0...first_part_size]
      else
        line[(first_part_size + (p - 1)*Term::Size.width)...(first_part_size + p*Term::Size.width)]
      end
    end

    # Returns the height of this line, (1 on common lines, more on wrapped lines):
    private def line_height(line)
      1 + (@prompt_size + line.size) // Term::Size.width
    end

    private def expression_height
      @lines.sum { |l| line_height(l) }
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

    def move_cursor_to(x, y)
      if y > @y || (y == @y && x > @x)
        # destination is after, move cursor forward:
        until {@x, @y} == {x, y}
          move_cursor_right
          raise "Bug: position (#{x}, #{y}) missed when moving cursor forward" if @y > y
        end
      else
        # destination is before, move cursor backward:
        until {@x, @y} == {x, y}
          move_cursor_left
          raise "Bug: position (#{x}, #{y}) missed when moving cursor backward" if @y < y
        end
      end
    end

    def move_cursor_to_begin
      move_cursor_to(0, 0)
    end

    def move_cursor_to_end
      y = @lines.size - 1

      move_cursor_to(@lines[y].size, y)
    end

    def move_cursor_to_end_of_first_line
      move_cursor_to(@lines[0].size, 0)
    end

    # Clear the screen, yields for modifications, and displays the new expression.
    # cursor is adjusted to not overflow if the new expression is smaller.
    def update(force_full_view = false, &)
      print Term::Cursor.hide
      clear_screen

      with self yield

      @expression = nil

      # Updated expression can be smaller and we might need to adjust the cursor:
      @y = @y.clamp(0, @lines.size - 1)
      @x = @x.clamp(0, @lines[@y].size)

      print_expression(force_full_view)
      print Term::Cursor.show
    end

    def replace(lines : Array(String))
      update { @lines = lines.dup }
    end

    def end_editing(replace : Array(String)? = nil)
      if replace
        update(force_full_view: true) { @lines = replace }
      elsif expression_height >= Term::Size.height
        update(force_full_view: true) { }
      end

      move_cursor_to_end
      puts
    end

    def prompt_next
      @scroll_offset = 0
      @lines = [""]
      @expression = nil
      reset_cursor
      print @prompt.call(0)
    end

    def scroll_up
      if @scroll_offset < expression_height() - Term::Size.height
        @scroll_offset += 1
        update { }
      end
    end

    def scroll_down
      if @scroll_offset > 0
        @scroll_offset -= 1
        update { }
      end
    end

    private def view_bounds
      h = Term::Size.height
      end_ = expression_height() - 1

      start = {0, end_ + 1 - h}.max

      @scroll_offset = @scroll_offset.clamp(0, start)

      start -= @scroll_offset
      end_ -= @scroll_offset
      {start, end_}
    end

    # Clean the screen, cursor stay unchanged but real cursor is set to the beginning of expression:
    private def clear_screen
      if expression_height >= Term::Size.height
        print Term::Cursor.row(1)
      else
        x_save, y_save = @x, @y
        move_cursor_to_begin
        @x, @y = x_save, y_save
      end

      print Term::Cursor.column(1)
      print Term::Cursor.clear_screen_down
    end

    private def print_line(colorized_line, line_index, line_size, prompt?, first?, is_last_part?)
      if prompt?
        puts unless first?
        print @prompt.call(line_index)
      end
      print colorized_line

      # ```
      # prompt> begin                  |
      # prompt>   foooooooooooooooooooo|
      #                                | <- If the line size match exactly the screen width, we need to add a
      # prompt>   bar                  |    extra line feed, so computes based on `%` or `//` stay exact.
      # prompt> end                    |
      # ```
      puts if is_last_part? && remainding_size(line_size) == 0
    end

    # Prints the colorized expression, this last is clipped if it's higher than screen.
    # The only displayed part of the expression is delimited by `view_bounds` and depend of the value of
    # `@scroll_offset`.
    # Lines that takes more than one line (if wrapped) are cut in consequence.
    private def print_expression(force_full_view = false)
      if force_full_view
        start, end_ = 0, Int32::MAX
      else
        start, end_ = view_bounds()
      end

      colorized_lines = @highlighter.highlight(self.expression).split('\n')

      first = true

      y = 0

      # Track the real cursor position so we are able to correctly retrieve it to its original position (before clearing screen):
      real_cursor_x = real_cursor_y = 0

      # Iterate over the uncolored lines because we need to know the true size of each line:
      @lines.each_with_index do |line, line_index|
        line_height = line_height(line)

        if start <= y && y + line_height - 1 <= end_
          # The line can hold entirely between the view bound, print it:
          print_line(colorized_lines[line_index], line_index, line.size, prompt?: true, first?: first, is_last_part?: true)
          first = false

          real_cursor_x = line.size
          real_cursor_y = line_index

          y += line_height
        else
          # The line cannot holds entirely between the view bound, we need to check each part individually:
          line_height.times do |part_number|
            if start <= y <= end_
              # The part holds on the view, we can print it.
              # FIXME:
              # /!\ Because we cannot extract the part from the colorized line (inserted escape colors makes impossible to know when it wraps), we need to
              # recolor the part individually.
              # This lead to a wrong coloration!, but should not happen often (wrapped long lines, on expression higher than screen, scrolled on border of the view).
              colorized_line = @highlighter.highlight(part(line, part_number))

              print_line(colorized_line, line_index, line.size, prompt?: part_number == 0, first?: first, is_last_part?: part_number == line_height - 1)
              first = false

              real_cursor_x = {line.size, (part_number + 1)*Term::Size.width - @prompt_size - 1}.min
              real_cursor_y = line_index
            end
            y += 1
          end
        end
      end

      # Retrieve the real cursor at its corresponding cursor position (`@x`, `@y`)
      x_save, y_save = @x, @y
      @y = real_cursor_y
      @x = real_cursor_x
      move_cursor_to(x_save, y_save)
    end
  end
end
