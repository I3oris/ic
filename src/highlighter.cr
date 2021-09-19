# File retake and modified from https://github.com/crystal-community/icr/blob/master/src/icr/highlighter.cr
# Thanks!
class IC::Highlighter
  COMMENT_COLOR           = {:dark_gray, :bold}
  NUMBER_COLOR            = :magenta
  CHAR_COLOR              = :magenta
  SYMBOL_COLOR            = :magenta
  STRING_COLOR            = :light_yellow
  HEREDOC_DELIMITER_COLOR = {:light_yellow, :underline}
  INTERPOLATION_COLOR     = :light_red
  CONST_COLOR             = {:blue, :underline}
  OPERATOR_COLOR          = :light_red
  IDENT_COLOR             = :default
  KEYWORD_COLOR           = :light_red
  TRUE_FALSE_NIL_COLOR    = {:cyan, :bold}
  SELF_COLOR              = {:cyan, :bold}
  SPECIAL_VALUES_COLOR    = :cyan
  METHOD_COLOR            = {:green, :bold}

  KEYWORDS = {
    :abstract, :alias, :annotation, :as, :as?, :asm, :begin, :break, :case, :class,
    :def, :do, :else, :elsif, :end, :ensure, :enum, :extend, :for, :fun,
    :if, :in, :include, :instance_sizeof, :is_a?, :lib, :macro, :module,
    :next, :nil?, :of, :offsetof, :out, :pointerof, :private, :protected, :require,
    :rescue, :responds_to?, :return, :select, :sizeof, :struct, :super,
    :then, :type, :typeof, :undef, :union, :uninitialized, :unless, :until,
    :verbatim, :when, :while, :with, :yield,
  }

  SPECIAL_VALUES = {:__FILE__, :__DIR__, :__LINE__, :__END_LINE__}
  TRUE_FALSE_NIL = {:true, :false, :nil}
  SPECIAL_WORDS  = /^(new|loop|raise|record|spawn|(class_)?(getter|property|setter)(\?|!)?)$/

  OPERATORS = {
    :+, :-, :*, :/, ://,
    :"=", :==, :<, :<=, :>, :>=, :!, :!=, :=~, :!~,
    :[], :[]?, :[]=, :<=>, :===,
    :&, :|, :^, :~, :**, :>>, :<<, :%,
    :&+, :&-, :&*, :&**,
    :"+=", :"-=", :"*=", :"/=", :"//=",
    :"&=", :"|=", :"^=", :"**=", :">>=", :"<<=", :"%=",
    :"&+=", :"&-=", :"&*=",
    :"&&", :"||", :"&&=", :"||=",
  }

  def initialize
    @colorized = ""
    @pos = 0
  end

  def self.highlight(code)
    self.new.highlight(code)
  end

  def highlight(code : String)
    @pos = 0
    error = false

    if code == "∅"
      return "∅".colorize.bold.red.to_s
    end

    lexer = Crystal::Lexer.new(code)
    lexer.comments_enabled = true
    lexer.count_whitespace = true
    lexer.wants_raw = true

    # Colorize the *code* following the `Lexer`:
    @colorized = String.build(64 + code.bytesize*2) do |io|
      begin
        highlight_normal_state lexer, io
        io.print "\e[m"
      rescue
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
    if error
      @colorized += String.new(code.to_slice[@pos..])
    end

    return @colorized
  end

  private def highlight_normal_state(lexer, io, break_on_rcurly = false)
    last_is_def = false
    heredoc_stack = [] of Crystal::Token
    last_token = {type: nil, value: ""}

    loop do
      @pos = lexer.current_pos
      token = lexer.next_token

      case token.type
      when :NEWLINE
        io.puts
        heredoc_stack.each_with_index do |t, i|
          highlight_delimiter_state lexer, t, io, heredoc: true
          unless i == heredoc_stack.size - 1
            # Next token to heredoc's end is either NEWLINE or EOF.
            @pos = lexer.current_pos
            if lexer.next_token.type == :EOF
              raise "Unterminated heredoc"
            end
            io.puts
          end
        end
        heredoc_stack.clear
      when :SPACE
        io << token.value
      when :COMMENT
        highlight token.value.to_s, COMMENT_COLOR, io
      when :NUMBER
        highlight token.raw, NUMBER_COLOR, io
      when :CHAR
        highlight token.raw, CHAR_COLOR, io
      when :SYMBOL
        highlight token.raw, SYMBOL_COLOR, io
      when :CONST, :"::"
        highlight token, CONST_COLOR, io
      when :DELIMITER_START
        if token.raw == "/" && last_token[:type].in?(:NUMBER, :CONST, :INSTANCE_VAR, :CLASS_VAR, :IDENT)
          highlight "/", OPERATOR_COLOR, io
        elsif token.delimiter_state.kind == :heredoc
          highlight token.raw, HEREDOC_DELIMITER_COLOR, io
          heredoc_stack << token.dup
        else
          highlight_delimiter_state lexer, token, io
        end
      when :STRING_ARRAY_START, :SYMBOL_ARRAY_START
        highlight_string_array lexer, token, io
      when :EOF
        break
      when :IDENT
        if last_is_def
          last_is_def = false
          highlight token, METHOD_COLOR, io
        elsif SPECIAL_WORDS.matches? token.to_s
          highlight token, KEYWORD_COLOR, io
        else
          highlight token, ident_color(token), io
        end
      when .in? SPECIAL_VALUES
        highlight token, SPECIAL_VALUES_COLOR, io
      when :"}"
        if break_on_rcurly
          highlight "}", INTERPOLATION_COLOR, io
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
          highlight last_token[:value] + ':', SYMBOL_COLOR, io
        else
          io << ':'
        end
      when :UNDERSCORE
        io << "_"
      else
        if OPERATORS.includes? token.type
          highlight token, OPERATOR_COLOR, io
        else
          io << token
        end
      end

      last_token = {type: token.type, value: token.value.as?(String) || ""}

      unless token.type == :SPACE
        last_is_def = %i(def class module lib macro).any? { |t| token.keyword?(t) }
      end
    end
  end

  private def ident_color(token)
    case token.value
    when .in? KEYWORDS       then KEYWORD_COLOR
    when .in? TRUE_FALSE_NIL then TRUE_FALSE_NIL_COLOR
    when :self               then SELF_COLOR
    else                          IDENT_COLOR
    end
  end

  private def highlight_delimiter_state(lexer, token, io, heredoc = false)
    highlight token.raw, STRING_COLOR, io unless heredoc

    loop do
      @pos = lexer.current_pos
      token = lexer.next_string_token(token.delimiter_state)
      case token.type
      when :DELIMITER_END
        if heredoc
          highlight_multiline token.raw, HEREDOC_DELIMITER_COLOR, io
        else
          highlight token.raw, STRING_COLOR, io
        end
        break
      when :INTERPOLATION_START
        highlight "\#{", INTERPOLATION_COLOR, io
        highlight_normal_state lexer, io, break_on_rcurly: true
      when :EOF
        break
      else
        highlight_multiline token.raw, STRING_COLOR, io
      end
    end
  end

  private def highlight_string_array(lexer, token, io)
    highlight token.raw, STRING_COLOR, io
    loop do
      consume_space_or_newline(lexer, io)
      @pos = lexer.current_pos
      token = lexer.next_string_array_token
      case token.type
      when :STRING
        highlight token.raw, STRING_COLOR, io
      when :STRING_ARRAY_END
        highlight token.raw, STRING_COLOR, io
        break
      when :EOF
        if token.delimiter_state.kind == :string_array
          raise "Unterminated string array literal"
        else # == :symbol_array
          raise "Unterminated symbol array literal"
        end
      else
        raise "Bug: shouldn't happen"
      end
    end
  end

  private def consume_space_or_newline(lexer, io)
    loop do
      char = lexer.current_char
      case char
      when '\n'
        lexer.next_char
        lexer.incr_line_number 1
        io.puts
      when .ascii_whitespace?
        lexer.next_char
        io << char
      else
        break
      end
    end
  end

  private def highlight(token : Crystal::Token | String, color : Symbol, io)
    io << token.colorize(color)
  end

  private def highlight(token : Crystal::Token | String, color : Tuple(Symbol, Symbol), io)
    io << token.colorize(color[0]).mode(color[1])
  end

  # When the token starts with '\n', start colorizing only after the '\n',
  # so a prompt can be inserted without color conflict.
  private def highlight_multiline(token : String, color, io)
    if token.starts_with? '\n'
      io.puts
      highlight token[1..], color, io
    else
      highlight token, color, io
    end
  end
end
