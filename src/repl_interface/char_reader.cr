module IC::ReplInterface
  module CharReader
    def self.read_chars(io = STDIN, &)
      slice_buffer = Bytes.new(1024)

      loop do
        nb_read = raw(io) { io.read(slice_buffer) }

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
        case chars[1]?
        when '['.ord
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
            elsif chars[3]? == '~'.ord # linux console HOME
              :move_cursor_to_begin
            end
          when '4'.ord # linux console END
            if chars[3]? == '~'.ord
              :move_cursor_to_end
            end
          when 'H'.ord # xterm HOME
            :move_cursor_to_begin
          when 'F'.ord # xterm END
            :move_cursor_to_end
          end
        when '\t'.ord
          :shift_tab
        when '\r'.ord
          :insert_new_line
        when 'O'.ord
          if chars[2]? == 'H'.ord # gnome terminal HOME
            :move_cursor_to_begin
          elsif chars[2]? == 'F'.ord # gnome terminal END
            :move_cursor_to_end
          end
        else
          :escape
        end
      when '\r'.ord, '\n'.ord
        :enter
      when '\t'.ord
        :tab
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

    private def self.raw(io : T, &) forall T
      {% if T.has_method?(:raw) %}
        io.raw { yield io }
      {% else %}
        yield io
      {% end %}
    end

    private def self.ctrl(k)
      (k.ord & 0x1f)
    end
  end
end
