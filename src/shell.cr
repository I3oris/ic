module ICR
  class Shell
    CRYSTAL_VERSION = "1.0.0"

    @reader = Term::Reader.new(interrupt: :exit, history_duplicates: false)
    @highlighter = ICR::Highlighter.new
    @edited_line = ""
    @prompt = :normal
    @line_number = 0
    @need_multiline = false
    @edited_multiline = ""
    @indent = 0
    @history = [""]
    @history_index = -1

    private def prompt(nb = nil) : String
      n = sprintf("%02d", (nb || @line_number))
      p = "icr(#{CRYSTAL_VERSION}):".colorize.default
      p = "#{p}#{n.colorize.magenta}"
      case @prompt
      when :normal  then p += "> "
      when :special then p += "* "
      end
      p
    end

    private def clear_line
      print "\r"
      print prompt
    end

    private def formate_line
      print "\r"
      nb_lines = @edited_line.split('\n').size
      if (nb_lines > 2)
        nb_lines.times do
          print "\033[1F"
        end
      end
      # colored, error = highlighter.highlight()
      # formated = Crystal.format(@edited_line)
      formated = @edited_line
      print @highlighter.highlight(formated, @line_number - nb_lines + 1).chomp("\n")
    end

    private def highlight_line
      print "\r"
      print @highlighter.highlight(@edited_line, @line_number).chomp("\n")
    end

    private def replace_line(line)
      clear_line
      print " "*@edited_line.size
      @edited_line = line
      highlight_line
    end

    private def must_indent?(line)
      # TODO handle ALL keyword indent
      (line.starts_with? /( )*(class|struct|def|if|unless|while|until|module|lib|begin)/) ||
        line =~ /( )*do( )*/
    end

    private def add_to_history(line)
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

    def run(display_result)
      @highlighter.invitation = ->(nb : Int32) do
        self.prompt nb
      end
      print prompt
      loop do
        char = @reader.read_keypress
        case char
        #  Ctrl-x
        when "\u0018"
          exit
        when .nil?
          exit
        when "\r"
          if @edited_line.empty?
            puts
            @line_number += 1
            print prompt
            next
          end
          status = yield @edited_line, @edited_multiline
          need_multiline = (status == :multiline)
          formate_line unless need_multiline || @need_multiline || status == :error
          puts
          @line_number += 1
          if need_multiline
            @prompt = :special
            @indent += 1 if self.must_indent?(@edited_line)
            @need_multiline = need_multiline
            @edited_multiline += @edited_line + "\n"
          elsif !need_multiline && @need_multiline
            @indent = 0
            @prompt = :normal
            @need_multiline = false
            # @edited_line = @edited_multiline
            @edited_line = @edited_multiline + @edited_line
            formate_line
            puts
            @line_number += 1
            @edited_multiline = ""
          end

          self.add_to_history @edited_line
          @edited_line = "  "*@indent
          display_result.call
          print prompt
          print "  "*@indent
          # up
        when "\e[A"
          self.history_up
          # down
        when "\e[B"
          self.history_down
          # left
        when "\e[D"
          # right
        when "\e[C"
          # back
        when "\u007f"
          clear_line
          print " "*@edited_line.size
          @edited_line = @edited_line.rchop
          highlight_line
          # (last letter of "end")
          # when "d"
          #   @edited_line += char
          #   if @indent >= 1 && @edited_line =~ /( )*end( )*/
          #     @indent -= 1
          #     clear_line
          #     print " "*@edited_line.size
          #     @edited_line = "  "*@indent + "end"
          #     highlight_line
          #   else
          #     highlight_line
          #   end
          # (last letter of "else")
          # when "e"
        else
          @edited_line += char
          if @indent >= 1 && @edited_line =~ /( )*end( )*/
            @indent -= 1
            replace_line("  "*@indent + "end")
            # clear_line
            # print " "*@edited_line.size
            # @edited_line = "  "*@indent + "end"
            # highlight_line
          elsif @indent >= 1 && @edited_line =~ /( )*else( )*/
            # @indent -= 1
            replace_line("  "*(@indent - 1) + "else")
          else
            highlight_line
          end
          # puts char.inspect
          # @edited_line += char
          # highlight_line
        end
      end
    end
  end
end
