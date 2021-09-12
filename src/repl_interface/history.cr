module IC::REPLInterface
  class History
    @history = [] of Array(String)
    @index = 0

    def <<(lines)
      if l = @history.delete(lines)
        @history.push(l)
      else
        @history.push(lines)
      end

      @index = @history.size
    end

    def clear
      @history.clear
      @index = 0
    end

    def up(&)
      unless @index == 0
        @index -= 1
        yield @history[@index].dup
      end
    end

    def down(&)
      unless @index == @history.size
        @index += 1
        yield @history[@index]?.try &.dup || [""]
      end
    end
  end
end
