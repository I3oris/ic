module ICR
  class CharReader
    class Interuption < Exception
    end

    @@io : IO::FileDescriptor = STDIN

    def self.read_chars(@@io, &)
      c = nil
      loop do
        @@io.raw { c = self.next }
        yield c if c
      rescue Interuption
        puts
        exit(0)
      end
    end

    def self.next
      c = @@io.read_char
      case c
      when '\e'
        if @@io.read_char == '['
          case @@io.read_char
          when 'A' then :up
          when 'B' then :down
          when 'C' then :right
          when 'D' then :left
          end
        end
        # ctrl-c, ctrl-d, ctrl-x
      when '\u0003', '\u0004', '\u0018'
        raise Interuption.new
      when '\u007f'
        :back
      else
        c
      end
    end
  end

  class Shell
    @edited_line = ""
    @prompt_type = :normal
    @line_number = 0
    @indent = 0
    @history = [""]
    @history_index = -1

    private getter? multiline = false

    private def prompt(nb = nil) : String
      n = sprintf("%02d", (nb || @line_number))
      # p = "icr(1.0.0):#{n}"
      p = "icr(#{Crystal::VERSION}):".colorize(:white)
      p = "#{p}#{n.colorize.magenta}"
      if multiline?
        p += "* "
      else
        p += "> "
      end
      p
    end

    private def clear_line
      lines = @edited_line.split('\n')
      lines.reverse_each do |l|
        print '\r'
        (l.size + 15).times { print ' ' }
        print '\r'
        print "\033[1F"
      end
      puts
      lines.size
    end

    private def formate_line
      nb_lines = clear_line
      {% unless flag?(:no_semantic) %}
        @edited_line = Crystal.format(@edited_line).chomp("\n")
      {% end %}
      print Highlighter.highlight(@edited_line, @line_number - nb_lines)
    end

    private def highlight_line
      clear_line
      print Highlighter.highlight(@edited_line, @line_number) # - nb_lines+1
    end

    private def replace_line(line)
      clear_line
      @edited_line = line
      print Highlighter.highlight(@edited_line, @line_number)
    end

    private def increase_indent
      last_line = @edited_line.split('\n')[-1]
      # TODO handle ALL keyword indent
      if (last_line.starts_with? /( )*(class|struct|def|if|unless|while|until|module|lib|begin|case)/) ||
         last_line =~ /( )*do( )*/
        @indent += 1
      end
    end

    private def auto_unindent(lines, indent, keyword)
      l = String.build do |str|
        str << lines[0...-1].join('\n')
        str << '\n'
        indent.times { str << "  " }
        str << keyword
      end
      replace_line(l)
    end

    private def auto_unindent
      if @indent < 1
        highlight_line
        return
      end

      lines = @edited_line.split('\n')
      case lines[-1]?
      when /^( )*end$/
        @indent -= 1
        auto_unindent(lines, @indent, "end")
      when /^( )*else$/
        auto_unindent(lines, @indent - 1, "else")
      when /^( )*elsif$/
        auto_unindent(lines, @indent - 1, "elsif")
      when /^( )*when$/
        auto_unindent(lines, @indent - 1, "when")
      else
        highlight_line
      end
    end

    private def add_to_history(line)
      @line_number += line.split('\n').size
      @history.push line
      @history_index = 0
    end

    private def history_up
      unless @history_index == @history.size - 1
        @history_index += 1
        replace_line @history[-@history_index]
      end
    end

    private def history_down
      unless @history_index == 0
        @history_index -= 1
        replace_line @history[-@history_index]
      end
    end

    private def validate_line
      @indent = 0
      @multiline = false
      self.add_to_history @edited_line
      @edited_line = ""
    end

    private def on_newline(display_result)
      if @edited_line.empty?
        @line_number += 1
        puts
        print prompt
        return
      end
      status = yield @edited_line

      case status
      when :error
        validate_line
      when :multiline
        self.increase_indent
        @multiline = true
        @edited_line += "\n" + "  "*@indent
      when :line
        formate_line
        validate_line
        display_result.call
      end
      puts
      print prompt
      print "  "*@indent
    end

    def run(display_result, &block : String -> Symbol)
      Highlighter.invitation = ->(nb : Int32) do
        self.prompt nb
      end
      print prompt

      CharReader.read_chars(STDIN) do |char|
        case char
        when '\r'  then on_newline(display_result, &block)
        when :up   then history_up
        when :down then history_down
        when :left
        when :right
        when :back then replace_line @edited_line.rchop
        when Char
          @edited_line += char
          self.auto_unindent
        end
      end
    end
  end
end
