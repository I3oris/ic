module IC
  class Quit < Exception
  end

  class Cancel < Exception
  end

  class CharReader
    @@io : IO::FileDescriptor = STDIN

    def self.read_chars(@@io, &)
      c = nil
      loop do
        @@io.raw { c = self.next }
        yield c if c
      rescue Quit
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
        raise Quit.new
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
    @indent = 0
    @history = [""]
    @history_index = -1

    private getter? multiline = false

    private def prompt : String
      n = sprintf("%02d", IC.code_lines.size + 1 + Highlighter.line_number)
      # p = "ic(1.0.0):#{n}"
      p = "ic(#{Crystal::VERSION}):".colorize(:white)
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
        # 20 = prompt size with 6-sized line number (eg <= 999999)
        (l.size + 20).times { print ' ' }
        print '\r'
        print "\033[1F"
      end
      puts
      lines.size
    end

    private def formate_line
      nb_lines = clear_line
      begin
        @edited_line = Crystal.format(@edited_line).chomp("\n")
      rescue
      end
      print Highlighter.highlight(@edited_line)
    end

    private def highlight_line
      colorized = Highlighter.highlight(@edited_line)
      clear_line
      print colorized
    end

    private def replace_line(line)
      clear_line
      @edited_line = line
      print Highlighter.highlight(@edited_line)
    end

    private def increase_indent
      return if Highlighter.is_str?

      last_line = @edited_line.split('\n')[-1]
      if (last_line.starts_with? /( )*(abstract|class|struct|enum|def|if|unless|while|until|module|lib|begin|case|macro|select|union)/) ||
         last_line =~ /( )*do( )*/ ||
         last_line.starts_with? /( )*\{\%( )*(for|if|unless|begin)/
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
      when /^( )*(else|elsif|when|in|rescue|ensure)$/
        auto_unindent(lines, @indent - 1, $~[2])
      when /^( )*\{\%( )*end$/
        @indent -= 1
        auto_unindent(lines, @indent, "{% end %}")
      else
        highlight_line
      end
    end

    private def add_to_history(line)
      @history.push line
      @history_index = 0
    end

    def clear_history
      @history = [""]
      @history_index = -1
    end

    private def history_up
      unless @history_index == @history.size - 1
        @history_index += 1
        replace_line @history[-@history_index]
      end
    end

    private def history_down
      unless @history_index <= 0
        @history_index -= 1
        replace_line @history[-@history_index]
      end
    end

    private def validate_line(*, no_history = false)
      @indent = 0
      @multiline = false
      unless no_history
        add_to_history @edited_line
      end
      @edited_line = ""
    end

    private def on_newline(&)
      formate_line

      case @edited_line
      when "# clear_history"
        validate_line no_history: true
        clear_history
        puts " => #{"✔".colorize.green}"
        IC.code_lines << @edited_line
        print prompt
        return
      when /^# (#{Commands.commands_regex_names})(( [a-z\-]+)*)/
        validate_line
        Commands.run_cmd($~[1]?, $~[2].split(" ", remove_empty: true))
        IC.code_lines << @edited_line
        print prompt
        return
      when .blank?, /^#.*/
        validate_line no_history: true
        IC.code_lines << @edited_line
        puts
        print prompt
        return

        # Replace lines starting by '.' by "__."
        # so ".foo" become "__.foo":
      when /^\.(?!\.)/ # don't match begin-less range ("..x")
        @edited_line = "__#{@edited_line}"
      end
      puts
      status = yield @edited_line

      case status
      when :error
        validate_line
      when :multiline
        self.increase_indent
        @multiline = true
        @edited_line += "\n" + "  "*@indent
      when :line
        validate_line
        IC.display_result
      end
      print prompt
      print "  "*@indent
      highlight_line if status == :multiline
    end

    def run(&block : String -> Symbol)
      Highlighter.invitation = ->prompt
      print prompt

      CharReader.read_chars(STDIN) do |char|
        case char
        when '\r'  then on_newline(&block)
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
