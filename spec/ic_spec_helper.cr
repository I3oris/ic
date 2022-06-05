require "../src/ic"

module IC::Spec
  @@repl = Crystal::Repl.new
  @@repl.public_load_prelude

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
end
