# File retake from https://github.com/crystal-community/icr/blob/master/src/icr/highlighter.cr
# thanks!
class ICR::Highlighter
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

  @@num_line = 0
  class_setter invitation : Proc(Int32, String) = ->(nb : Int32) { "" }

  def self.invitation
    i = @@invitation.call(@@num_line)
    @@num_line += 1
    i
  end

  KEYWORDS = Set{
    "new",
    :abstract, :alias, :as, :as?, :asm, :begin, :break, :case, :class,
    :def, :do, :else, :elsif, :end, :ensure, :enum, :extend, :for, :fun,
    :if, :in, :include, :instance_sizeof, :is_a?, :lib, :macro, :module,
    :next, :nil?, :of, :out, :pointerof, :private, :protected, :require,
    :rescue, :responds_to?, :return, :select, :sizeof, :struct, :super,
    :then, :type, :typeof, :undef, :union, :uninitialized, :unless, :until,
    :when, :while, :with, :yield,
  }

  SPECIAL_VALUES = Set{
    :true, :false, :nil, :self,
    :__FILE__, :__DIR__, :__LINE__, :__END_LINE__,
  }

  OPERATORS = Set{
    :"+", :"-", :"*", :"/",
    :"=", :"==", :"<", :"<=", :">", :">=", :"!", :"!=", :"=~", :"!~",
    :"&", :"|", :"^", :"~", :"**", :">>", :"<<", :"%",
    :"[]", :"[]?", :"[]=", :"<=>", :"===",
  }

  def self.highlight(code, @@num_line = 0,*, no_invitation = false)
    highlight_stack.clear
    lexer = Crystal::Lexer.new(code)
    lexer.comments_enabled = true
    lexer.count_whitespace = true
    lexer.wants_raw = true

    String.build do |io|
      io.print self.invitation unless no_invitation
      begin
        highlight_normal_state lexer, io
        io.puts "\e[m"
      rescue Crystal::SyntaxException
      end
    end.chomp("\n")
  end

  private def self.highlight_normal_state(lexer, io, break_on_rcurly = false)
    last_is_def = false

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
        highlight_delimiter_state lexer, token, io
      when :STRING_ARRAY_START, :SYMBOL_ARRAY_START
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

      unless token.type == :SPACE
        last_is_def = token.keyword? :def
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
        break
      when :INTERPOLATION_START
        end_highlight io
        highlight "\#{", :interpolation, io
        highlight_normal_state lexer, io, break_on_rcurly: true
        start_highlight :string, io
      when :EOF
        break
      else
        print_raw io, token.raw
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
    io << raw.to_s.gsub("\n", "\n#{self.invitation}")
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
    when :number, :char
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
