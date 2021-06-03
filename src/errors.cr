module IC
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
    puts ("\nIC(UNKNOWN BUG):").colorize.red.bold.to_s
    puts inspect_with_backtrace
  end
end

class Crystal::CodeError
  def display
    puts
    self.color = true
    self.error_trace = true

    if self.is_a? ErrorFormat
      print IC.program.filename ? "In " : "At "
      puts self.format_error(
        filename: IC.program.filename || "",
        lines: self.lines,
        line_number: self.line_number,
        column_number: self.column_number,
        size: self.size
      )
      puts "Error: #{self.message}".colorize.yellow.bold
      self.inner.try &.display if responds_to? :inner
    else
      puts self
    end
  end

  def lines
    if responds_to?(:location) && (filename = self.location.filename).is_a? VirtualFile
      filename.source.lines.to_a
    else
      IC.code_lines
    end
  end
end

class Crystall::Error
  def display
    puts
    puts "Error: #{self.message}".colorize.yellow.bold
  end
end

class Crystal::Error < Exception
  # Dirtily catches exceptions for unterminated syntax, such as "class Foo", or "{", so the
  # user have a change to terminate his expressions.
  def unterminated?
    self.message.in?({
      "expecting identifier 'end', not 'EOF'",
      "expecting token 'CONST', not 'EOF'",
      "expecting any of these tokens: IDENT, CONST, `, <<, <, <=, ==, ===, !=, =~, !~, >>, >, >=, +, -, *, /, //, !, ~, %, &, |, ^, **, [], []?, []=, <=>, &+, &-, &*, &** (not 'EOF')",
      "expecting token ')', not 'EOF'",
      "expecting token ']', not 'EOF'",
      "expecting token '}', not 'EOF'",
      "expecting token '%}', not 'EOF'",
      "expecting token ']', not ','",
      "expecting token '}', not ','",
      "expected '}' or named tuple name, not EOF",
      "unexpected token: NEWLINE",
      "unexpected token: EOF",
      "unexpected token: EOF (expecting when, else or end)",
      "unexpected token: EOF (expecting ',', ';' or '\n')",
      "Unexpected EOF on heredoc identifier",
      "unterminated parenthesized expression",
      "Unterminated string literal",
      "unterminated hash literal",
      "Unterminated command literal",
      "unterminated array literal",
      "unterminated tuple literal",
      "unterminated macro",
      "Unterminated string interpolation",
      # ^ U is sometime upcase, sometime downcase :o
      "invalid trailing comma in call",
      "unknown token: '\\u{0}'",
    }) || self.message.try &.matches? /Unterminated heredoc: can't find ".*" anywhere before the end of file/
  end
end

def bug!(msg)
  raise IC::Error.new ("\nIC(BUG): #{msg}").colorize.red.bold.to_s
end

def todo(msg)
  raise IC::Error.new ("\nIC(TODO): #{msg}").colorize.blue.bold.to_s
end

def ic_error(msg)
  raise IC::Error.new ("\nIC: #{msg}").colorize.magenta.bold.to_s
end
