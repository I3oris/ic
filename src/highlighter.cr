# File retake and modified from https://github.com/crystal-community/icr/blob/master/src/icr/highlighter.cr
# Thanks!
module IC::Highlighter
  record Highlight,
    color : Symbol,
    bold : Bool = false,
    underline : Bool = false do
    def to_s(io)
      case color
      when :black   then io << 30
      when :red     then io << 31
      when :green   then io << 32
      when :yellow  then io << 33
      when :blue    then io << 34
      when :magenta then io << 35
      when :cyan    then io << 36
      when :white   then io << 37
      end
      io << ";1" if bold
      io << ";4" if underline
    end
  end

  class_getter highlight_stack = [] of Highlight

  class_getter? is_str = false
  class_getter line_number = 0
  class_setter invitation : Proc(String) = ->{ "" }
  @@no_invitation = false

  def self.invitation
    invit = @@no_invitation ? "" : @@invitation.call
    @@line_number += 1
    invit
  end

  KEYWORDS = Set{
    "new",
    :abstract, :alias, :as, :as?, :asm, :begin, :break, :case, :class,
    :def, :do, :else, :elsif, :end, :ensure, :enum, :extend, :for, :fun,
    :if, :in, :include, :instance_sizeof, :is_a?, :lib, :macro, :module,
    :next, :nil?, :of, :out, :pointerof, :private, :protected, :require,
    :rescue, :responds_to?, :return, :select, :sizeof, :struct, :super,
    :then, :type, :typeof, :undef, :union, :uninitialized, :unless, :until,
    :verbatim, :when, :while, :with, :yield, :annotation,
  }

  SPECIAL_VALUES = Set{
    :true, :false, :nil, :self,
    :__FILE__, :__DIR__, :__LINE__, :__END_LINE__,
  }

  SPECIAL_WORDS = /^(new|(class_)?(getter|property|setter)(\?|!)?|loop|raise|record|spawn)$/

  OPERATORS = Set{
    :"+", :"-", :"*", :"/", :"//",
    :"=", :"==", :"<", :"<=", :">", :">=", :"!", :"!=", :"=~", :"!~",
    :"&", :"|", :"^", :"~", :"**", :">>", :"<<", :"%",
    :"[]", :"[]?", :"[]=", :"<=>", :"===",
    :"+=", :"-=", :"*=", :"/=", :"//=", :"|=", :"&=", :"%=",
  }

  def self.highlight(code, *, @@no_invitation = false)
    @@is_str = false
    @@line_number = 0
    highlight_stack.clear
    error = false

    lexer = Crystal::Lexer.new(code)
    lexer.comments_enabled = true
    lexer.count_whitespace = true
    lexer.wants_raw = true

    # Colorize the *code* following the `Lexer`:
    colorized = String.build do |io|
      io.print self.invitation
      begin
        highlight_normal_state lexer, io
        io.puts "\e[m"
      rescue Crystal::SyntaxException
        error = true
      end
    end

    # Some `SyntaxException` are raised when a token in being parsed, in this case the begin
    # of the token is lost.
    # For example when "def initialize(@" is written, Unknown token '\0' is raised, but only
    # "def initialize(" have been displayed on the screen,
    # in this case we want retrieve the "@".
    #
    # In the case of "def initialize(@[\^|-**/{" we want also retrieve the "@[\^|-**/{" because the user want
    # see what he write even it have no sense.
    #
    # So we compare what it have been written(colorized) and the original code, and add the difference,
    # but we must remove colors and invitation before comparing.
    if error
      # uncolorize:
      colorless = colorized.gsub(/\e\[[0-9;]*m/, "")

      # remove ic invitation:
      colorless = colorless.gsub(/ic\([0-9\.]+(-dev)?\):[0-9]{2,}[>\*"] /, "")

      # remove the \b\b\b and remove the erased char from colorless.size:
      backchar_size = 0
      colorless = colorless.gsub(/#{'\b'}+/) do |backs|
        backchar_size += backs.size
        ""
      end

      # The point where the exception have been raised, we want retrieve the lost characters after this:
      error_point = colorless.size - backchar_size

      # re-add missing characters and invitation:
      colorized += (code[error_point...].gsub "\n" { "\n#{self.invitation}" })
    end

    @@line_number = 0
    return colorized.chomp("\n")
  end

  private def self.highlight_normal_state(lexer, io, break_on_rcurly = false)
    last_is_def = false
    last_token = {type: nil, value: ""}

    while true
      token = lexer.next_token

      case token.type
      when :NEWLINE
        io.puts
        io.print "#{self.invitation}"
      when :SPACE
        io << token.value
        if token.passed_backslash_newline
          io.print "#{self.invitation}"
        end
      when :COMMENT
        highlight token.value.to_s, :comment, io
      when :NUMBER
        highlight token.raw, :number, io
      when :CHAR
        highlight token.raw, :char, io
      when :SYMBOL
        highlight token.raw, :symbol, io
      when :CONST, :"::"
        highlight token, :const, io
      when :DELIMITER_START
        @@is_str = true
        highlight_delimiter_state lexer, token, io
      when :STRING_ARRAY_START, :SYMBOL_ARRAY_START
        @@is_str = true
        highlight_string_array lexer, token, io
      when :EOF
        break
      when :IDENT
        if last_is_def
          last_is_def = false
          highlight token, :method, io
        else
          case
          when KEYWORDS.includes? token.value
            highlight token, :keyword, io
          when SPECIAL_VALUES.includes? token.value
            highlight token, :literal, io
          when SPECIAL_WORDS.matches? token.to_s
            highlight token, :keyword, io
          else
            io << token
          end
        end
      when :"}"
        if break_on_rcurly
          highlight token, :interpolation, io
          break
        else
          io << token
        end
      when :INSTANCE_VAR, :CLASS_VAR
        io << token.value
      when :GLOBAL, :GLOBAL_MATCH_DATA_INDEX
        io << token.value
      when :":"
        if last_token[:type] == :IDENT
          last_token[:value].size.times { io << '\b' }
          highlight last_token[:value] + ':', :symbol, io
        else
          io << ':'
        end
      else
        if OPERATORS.includes? token.type
          highlight token, :operator, io
        else
          case token.type
          when :UNDERSCORE
            io << "_"
          else
            io << token.type
          end
        end
      end

      last_token = {type: token.type, value: token.value.as?(String) || ""}

      unless token.type == :SPACE
        last_is_def = %i(def class module lib macro).any? { |t| token.keyword?(t) }
      end
    end
  end

  private def self.highlight_delimiter_state(lexer, token, io)
    start_highlight :string, io

    print_raw io, token.raw

    while true
      token = lexer.next_string_token(token.delimiter_state)
      case token.type
      when :DELIMITER_END
        print_raw io, token.raw
        end_highlight io
        @@is_str = false
        break
      when :INTERPOLATION_START
        end_highlight io
        highlight "\#{", :interpolation, io
        @@is_str = false
        highlight_normal_state lexer, io, break_on_rcurly: true
        @@is_str = true
        start_highlight :string, io
      when :EOF
        break
      else
        io.print(token.raw.to_s.gsub("\n") do
          invit = self.invitation
          "\n#{invit}\e[0;#{highlight_type(:string)}m"
        end)
      end
    end
  end

  private def self.highlight_string_array(lexer, token, io)
    start_highlight :string, io
    print_raw io, token.raw
    first = true
    while true
      lexer.next_string_array_token
      case token.type
      when :STRING
        io << " " unless first
        print_raw io, token.value
        first = false
      when :STRING_ARRAY_END
        @@is_str = false
        print_raw io, token.raw
        end_highlight io
        break
      when :EOF
        end_highlight io
        break
      end
    end
  end

  private def self.print_raw(io, raw)
    io << raw.to_s
  end

  private def self.highlight(token, type, io)
    start_highlight type, io
    io << token
    end_highlight io
  end

  private def self.start_highlight(type, io)
    @@highlight_stack << highlight_type(type)
    io << "\e[0;#{@@highlight_stack.last}m"
  end

  private def self.end_highlight(io)
    @@highlight_stack.pop
    io << "\e[0;#{@@highlight_stack.last?}m"
  end

  private def self.highlight_type(type)
    case type
    when :comment
      Highlight.new(:black, bold: true)
    when :number
      Highlight.new(:magenta)
    when :char
      Highlight.new(:magenta)
    when :symbol
      Highlight.new(:magenta)
    when :const
      Highlight.new(:blue, underline: true)
    when :string
      Highlight.new(:yellow)
    when :interpolation
      Highlight.new(:red, bold: true)
    when :keyword
      Highlight.new(:red)
    when :operator
      Highlight.new(:red)
    when :method
      Highlight.new(:green, bold: true)
    when :literal
      Highlight.new(:cyan, bold: true)
    else
      Highlight.new(:default)
    end
  end
end
