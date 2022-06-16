require "../src/repl"

module IC::ReplInterface::Term::Size
  # For spec, simulate of term size of 5 lines, and 15 characters wide:
  def self.size
    {15, 5}
  end
end

module IC::Spec
  @@repl = Crystal::Repl.new
  @@repl.run_prelude

  def self.auto_completion_handler
    handler = IC::ReplInterface::AutoCompletionHandler.new
    handler.set_context(@@repl)
    handler
  end

  def self.verify_completion(handler, code, should_be type, with_scope = "main")
    receiver, scope = handler.parse_receiver_code(code)
    receiver.try(&.type).to_s.should eq type
    scope.to_s.should eq with_scope
  end

  def self.expression_editor
    editor = IC::ReplInterface::ExpressionEditor.new do |line_number, _color?|
      # Prompt size = 5
      "p:#{sprintf("%02d", line_number)}>"
    end
    editor.output = IO::Memory.new
    editor.color = false
    editor
  end

  def self.verify_editor(editor, expression : String)
    editor.expression.should eq expression
  end

  def self.verify_editor(editor, x : Int32, y : Int32)
    {editor.x, editor.y}.should eq({x, y})
  end

  def self.verify_editor(editor, expression : String, x : Int32, y : Int32)
    self.verify_editor(editor, expression)
    self.verify_editor(editor, x, y)
  end

  def self.verify_editor_ouput(editor, output)
    editor.output.to_s.should eq output
  end

  def self.history_entries
    [
      [%(puts "Hello World")],
      [%(i = 0)],
      [
        %(while i < 10),
        %(  puts i),
        %(  i += 1),
        %(end),
      ],
    ]
  end

  def self.empty_history
    IC::ReplInterface::History.new
  end

  def self.history
    history = IC::ReplInterface::History.new
    self.history_entries.each { |e| history << e }
    history
  end

  def self.verify_history(history, entries, index)
    history.@history.should eq entries
    history.@index.should eq index
  end

  def self.verify_read_char(to_read, expect : Array)
    chars = [] of Char | Symbol | String?
    io = IO::Memory.new
    io << to_read
    io.rewind
    IC::ReplInterface::CharReader.read_chars(io) { |c| chars << c }
    chars.should eq expect
  end

  module MakePublic
    macro included
      {% for m in @type.methods.select(&.visibility.!= :public) %}
        {{m}}
      {% end %}
    end
  end
end

# Allow spec to test private methods
{% for klass in %w(
                  IC::ReplInterface::AutoCompletionHandler
                  IC::ReplInterface::ReplInterface
                  IC::ReplInterface::ExpressionEditor
                ) %}
  class {{klass.id}}
    include IC::Spec::MakePublic
  end
{% end %}
