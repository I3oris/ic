require "./ic_spec_helper"

describe Crystal::Repl do
  it "requires a local file" do
    repl = IC::SpecHelper.repl
    repl.verify_run_code(%(require "./spec/local_file.cr"), should_result_to: "nil")
  end

  it "requires a local file without extension" do
    repl = IC::SpecHelper.repl
    repl.verify_run_code(%(require "./spec/local_file"), should_result_to: "nil")
  end
end
