module IC::ReplInterface
  module CharReader
    def self.read_chars(io : T = STDIN, &) forall T
      slice_buffer = Bytes.new(1024)

      loop do
        nb_read =
          {% if T.has_method?(:raw) %}
            io.raw { io.read(slice_buffer) }
          {% else %}
            io.read(slice_buffer)
          {% end %}

        c = parse_escape_sequence(slice_buffer[0...nb_read])
        yield c if c

        break if c == :exit
      end
    end

    private def self.parse_escape_sequence(chars : Bytes) : Char | Symbol | String?
      return String.new(chars) if chars.size > 6
      return :exit if chars.empty?

      case chars[0]?
      when '\e'.ord
        if chars[1]? == '['.ord
          case chars[2]?
          when 'A'.ord then :up
          when 'B'.ord then :down
          when 'C'.ord then :right
          when 'D'.ord then :left
          when 'Z'.ord then :shift_tab
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
        elsif chars[1]? == '\t'.ord
          :shift_tab
        elsif chars[1]? == '\r'.ord
          :insert_new_line
        else
          :escape
        end
      when '\r'.ord, '\n'.ord
        :enter
      when ctrl('c')
        :keyboard_interrupt
      when ctrl('d'), ctrl('x'), '\0'.ord
        :exit
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
