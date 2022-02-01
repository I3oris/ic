module IC::ReplInterface
  module CharReader
    def self.read_chars(io = STDIN, &)
      slice_buffer = Bytes.new(1024)

      loop do
        nb_read = io.raw { io.read(slice_buffer) }

        c = parse_escape_sequence(slice_buffer[0...nb_read])
        yield c if c

        break if c == :exit
      end
    end

    private def self.parse_escape_sequence(chars : Bytes) : Char | Symbol | String?
      if chars.size > 6
        return String.new(chars)
      end

      case chars[0]?
      when '\e'.ord
        if chars[1]? == '['.ord
          case chars[2]?
          when 'A'.ord then :up
          when 'B'.ord then :down
          when 'C'.ord then :right
          when 'D'.ord then :left
          when '3'.ord
            if chars[3]? == '~'.ord
              :delete
            end
          when '1'.ord
            if {chars[3]?, chars[4]?} == {';'.ord, '5'.ord}
              case chars[5]?
              when 'A'.ord then :ctrl_up
              when 'B'.ord then :ctrl_down
              when 'C'.ord then :ctrl_right
              when 'D'.ord then :ctrl_left
              end
            end
          end
        end
      when '\r'.ord, '\n'.ord
        :enter
      when ctrl('c'), ctrl('d'), ctrl('x'), '\0'.ord
        :exit
      when ctrl('o')
        :insert_new_line
      when ctrl('a')
        :move_cursor_to_begin
      when ctrl('e')
        :move_cursor_to_end
      when 0x7f
        :back
      else
        if chars.size == 1
          chars[0].chr
        else
          String.new chars
        end
      end
    end

    private def self.ctrl(k)
      (k.ord & 0x1f)
    end
  end
end
