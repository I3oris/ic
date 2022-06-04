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
end
