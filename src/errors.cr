module ICR
  class Error < Exception
    def display
      puts self.message
    end
  end

  alias CompileTimeError = Crystal::Error
  # TODO RunTimeError
end

class Exception
  def display
    puts ("\nICR(UNKNOWN BUG): #{self.message}").colorize.red.bold.to_s
  end
end

class Crystal::Error
  def display
    puts

    # This kind of message need to display more informations:
    if self.message.try &.starts_with?(/instantiating|while requiring|expanding macro/)
      puts self.colorize.yellow.bold
    else
      puts self.message.colorize.yellow.bold
    end
  end

  def unterminated?
    self.message.in?({
      "expecting identifier 'end', not 'EOF'",
      "expecting token 'CONST', not 'EOF'",
      "expecting any of these tokens: IDENT, CONST, `, <<, <, <=, ==, ===, !=, =~, !~, >>, >, >=, +, -, *, /, //, !, ~, %, &, |, ^, **, [], []?, []=, <=>, &+, &-, &*, &** (not 'EOF')",
      "expecting token ')', not 'EOF'",
      "expecting token ']', not 'EOF'",
      "expecting token '}', not 'EOF'",
      "expected '}' or named tuple name, not EOF",
      "unexpected token: EOF",
      "unexpected token: EOF (expecting when, else or end)",
      "unexpected token: EOF (expecting ',', ';' or '\n')",
      "Unexpected EOF on heredoc identifier",
      "unterminated parenthesized expression",
      "Unterminated string literal", # <= U is upcase ^^
      "unterminated array literal",
      "unterminated tuple literal",
      "unterminated macro",
      "Unterminated string interpolation",
      "invalid trailing comma in call",
      "unknown token: '\\u{0}'",
    }) || self.message.try &.matches? /Unterminated heredoc: can't find ".*" anywhere before the end of file/
  end
end

def bug(msg)
  raise ICR::Error.new ("\nICR(BUG): #{msg}").colorize.red.bold.to_s
end

def todo(msg)
  raise ICR::Error.new ("\nICR(TODO): #{msg}").colorize.blue.bold.to_s
end

def icr_error(msg)
  raise ICR::Error.new ("\nICR: #{msg}").colorize.magenta.bold.to_s
end
