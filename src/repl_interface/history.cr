module IC::REPLInterface
  class History
    @history = [] of Array(String)
    @index = 0

    # Hold the history lines being edited, always contains one element more than @history
    # because it can also contain the current line (not yet in history)
    @edited_history = [nil] of Array(String)?

    def <<(lines)
      if l = @history.delete(lines)
        # re-insert duplicate elements at the end:
        @history.push(l)
      else
        @history.push(lines)
      end
      @index = @history.size

      @edited_history.fill(nil).push(nil)
    end

    def clear
      @history.clear
      @edited_history.clear.push(nil)
      @index = 0
    end

    def up(current_edited_lines : Array(String), &)
      unless @index == 0
        @edited_history[@index] = current_edited_lines

        @index -= 1
        yield @edited_history[@index]? || @history[@index]
      end
    end

    def down(current_edited_lines : Array(String), &)
      unless @index == @history.size
        @edited_history[@index] = current_edited_lines

        @index += 1
        yield @edited_history[@index]? || @history[@index]
      end
    end
  end
end
