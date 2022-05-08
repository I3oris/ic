# File retake and modified from https://github.com/crystal-community/icr/blob/master/src/icr/highlighter.cr
# Thanks!
class IC::Highlighter
  COMMENT_COLOR           = {:dark_gray, Colorize::Mode::Bold}
  NUMBER_COLOR            = :magenta
  CHAR_COLOR              = :light_yellow
  SYMBOL_COLOR            = :magenta
  STRING_COLOR            = :light_yellow
  HEREDOC_DELIMITER_COLOR = {:light_yellow, Colorize::Mode::Underline}
  INTERPOLATION_COLOR     = :light_red
  CONST_COLOR             = {:blue, Colorize::Mode::Underline}
  OPERATOR_COLOR          = :light_red
  IDENT_COLOR             = :default
  KEYWORD_COLOR           = :light_red
  KEYWORD_METHODS_COLOR   = :default
  TRUE_FALSE_NIL_COLOR    = {:cyan, Colorize::Mode::Bold}
  SELF_COLOR              = {:cyan, Colorize::Mode::Bold}
  SPECIAL_VALUES_COLOR    = :cyan
  METHOD_COLOR            = {:green, Colorize::Mode::Bold}

  KEYWORDS = {
    :abstract, :alias, :annotation, :asm, :begin, :break, :case, :class,
    :def, :do, :else, :elsif, :end, :ensure, :enum, :extend, :for, :fun,
    :if, :in, :include, :instance_sizeof, :lib, :macro, :module,
    :next, :of, :offsetof, :out, :pointerof, :private, :protected, :require,
    :rescue, :return, :select, :sizeof, :struct, :super,
    :then, :type, :typeof, :union, :uninitialized, :unless, :until,
    :verbatim, :when, :while, :with, :yield,
  }

  KEYWORD_METHODS = {
    :as, :as?, :is_a?, :nil?, :responds_to?,
  }

  SPECIAL_VALUES = {:__FILE__, :__DIR__, :__LINE__, :__END_LINE__}
  TRUE_FALSE_NIL = {:true, :false, :nil}
  SPECIAL_WORDS  = /^(new|loop|raise|record|spawn|(class_)?(getter|property|setter)(\?|!)?)$/

  OPERATORS = {
    :+, :-, :*, :/, ://,
    :"=", :==, :<, :<=, :>, :>=, :!, :!=, :=~, :!~,
    :<=>, :===,
    :&, :|, :^, :~, :**, :>>, :<<, :%,
    :&+, :&-, :&*, :&**,
    :"+=", :"-=", :"*=", :"/=", :"//=",
    :"&=", :"|=", :"^=", :"**=", :">>=", :"<<=", :"%=",
    :"&+=", :"&-=", :"&*=",
    :"&&", :"||", :"&&=", :"||=",
    :[], :[]?, :[]=,
  }

  def initialize
    @colorized = ""
    @pos = 0
  end

  def self.highlight(code, toggle = true)
    self.new.highlight(code, toggle: toggle)
  end

  def highlight(code : String, toggle = true)
    return code unless toggle

    @pos = 0
    error = false

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
      when .newline?
        io.puts
        heredoc_stack.each_with_index do |t, i|
          highlight_delimiter_state lexer, t, io, heredoc: true
          unless i == heredoc_stack.size - 1
            # Next token to heredoc's end is either NEWLINE or EOF.
            @pos = lexer.current_pos
            if lexer.next_token.type.eof?
              raise "Unterminated heredoc"
            end
            io.puts
          end
        end
        heredoc_stack.clear
      when .space?
        io << token.value
      when .comment?
        highlight token.value.to_s, COMMENT_COLOR, io
      when .number?
        highlight token.raw, NUMBER_COLOR, io
      when .char?
        highlight token.raw, CHAR_COLOR, io
      when .symbol?
        highlight token.raw, SYMBOL_COLOR, io
      when .const?, .op_colon_colon?
        highlight token, CONST_COLOR, io
      when .delimiter_start?
        last_token_type = last_token[:type]
        slash_is_not_regex = last_token_type && (
          last_token_type.number? ||
          last_token_type.const? ||
          last_token_type.instance_var? ||
          last_token_type.class_var? ||
          last_token_type.ident? ||
          last_token_type.op_rparen? ||
          last_token_type.op_rsquare? ||
          last_token_type.op_rcurly?
        )

        if token.raw == "/" && slash_is_not_regex
          highlight "/", OPERATOR_COLOR, io
        elsif token.delimiter_state.kind.heredoc?
          highlight token.raw, HEREDOC_DELIMITER_COLOR, io
          heredoc_stack << token.dup
        else
          highlight_delimiter_state lexer, token, io
        end
      when .string_array_start?, .symbol_array_start?
        highlight_string_array lexer, token, io
      when .eof?
        break
      when .ident?
        if last_is_def
          last_is_def = false
          highlight token, METHOD_COLOR, io
        elsif SPECIAL_WORDS.matches? token.to_s
          highlight token, KEYWORD_COLOR, io
        elsif lexer.current_char == ':'
          highlight "#{token}:", SYMBOL_COLOR, io
          lexer.reader.next_char if lexer.reader.has_next?
        else
          last_token_type = last_token[:type]
          if last_token_type && last_token_type.op_period?
            # Don't colorize keyword method e.g. `42.class`
            io << token
          else
            highlight token, ident_color(token), io
          end
        end
      when .magic_dir?, .magic_end_line?, .magic_file?, .magic_line?
        highlight token, SPECIAL_VALUES_COLOR, io
      when .op_rcurly?
        if break_on_rcurly
          highlight "}", INTERPOLATION_COLOR, io
          break
        else
          io << token
        end
      when .instance_var?, .class_var?
        io << token.value
      when .global?, .global_match_data_index?
        io << token.value
      when .underscore?
        io << "_"
        # These operators should not be colored:
      when .op_lparen?,                   # (
           .op_rparen?,                   # )
           .op_comma?,                    # ,
           .op_period?,                   # .
           .op_period_period?,            # ..
           .op_period_period_period?,     # ...
           .op_colon?,                    # :
           .op_semicolon?,                # ;
           .op_question?,                 # ?
           .op_at_lsquare?,               # @[
           .op_lsquare?,                  # [
           .op_lsquare_rsquare?,          # [] (avoid colorization of `[] of Foo`)
           .op_lsquare_rsquare_eq?,       # []=
           .op_lsquare_rsquare_question?, # []?
           .op_rsquare?,                  # ]
           .op_grave?,                    # `
           .op_lcurly?,                   # {
           .op_rcurly?                    # }
        io << token
      when .operator?
        last_token_type = last_token[:type]
        if last_token_type && last_token_type.op_period?
          # Don't colorize operators called as method e.g. `42.+ 1`
          io << token
        else
          highlight token, OPERATOR_COLOR, io
        end
      else
        io << token
      end

      last_token = {type: token.type, value: token.value.as?(String) || ""}

      unless token.type.space?
        last_is_def = %i(def class module lib macro).any? { |t| token.keyword?(t) }
      end
    end
  end

  private def ident_color(token)
    case token.value
    when .in? KEYWORDS        then KEYWORD_COLOR
    when .in? KEYWORD_METHODS then KEYWORD_METHODS_COLOR
    when .in? TRUE_FALSE_NIL  then TRUE_FALSE_NIL_COLOR
    when :self                then SELF_COLOR
    else                           IDENT_COLOR
    end
  end

  private def highlight_delimiter_state(lexer, token, io, heredoc = false)
    highlight token.raw, STRING_COLOR, io unless heredoc

    loop do
      @pos = lexer.current_pos
      token = lexer.next_string_token(token.delimiter_state)
      case token.type
      when .delimiter_end?
        if heredoc
          highlight_multiline token.raw, HEREDOC_DELIMITER_COLOR, io
        else
          highlight token.raw, STRING_COLOR, io
        end
        break
      when .interpolation_start?
        highlight "\#{", INTERPOLATION_COLOR, io
        highlight_normal_state lexer, io, break_on_rcurly: true
      when .eof?
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
      when .string?
        highlight token.raw, STRING_COLOR, io
      when .string_array_end?
        highlight token.raw, STRING_COLOR, io
        break
      when .eof?
        if token.delimiter_state.kind.string_array?
          raise "Unterminated string array literal"
        else # .symbol_array?
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

  private def highlight(token : Crystal::Token | String, color : Tuple(Symbol, Colorize::Mode), io)
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
