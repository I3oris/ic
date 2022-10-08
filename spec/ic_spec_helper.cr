require "../src/repl"

module IC
  class CrystalCompleter
    def verify_completion(code, should_be type, with_scope = "main")
      receiver, scope = self.semantics(code)
      receiver.try(&.type).to_s.should eq type
      scope.to_s.should eq with_scope
    end
  end

  class ::Crystal::Repl
    def verify_run_code(code, should_result_to result)
      self.run_next_code(code).to_s.should eq result
    end
  end

  module SpecHelper
    @@repl = Crystal::Repl.new
    @@repl.load_prelude

    def self.repl
      @@repl
    end

    def self.crystal_completer
      completer = CrystalCompleter.new
      completer.set_context(@@repl)
      completer
    end
  end
end
