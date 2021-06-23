require "spec"
require "../src/ic"

module IC
  def self.running_spec?
    true
  end

  def self.run_spec(code)
    VarStack.reset
    @@code_lines.clear
    @@program.vars.clear
    IC.parse(code).run.result
  end
end
