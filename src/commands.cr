module IC
  module Commands
    def self.run_cmd(name, args)
      puts
      case name
      when "reset" then IC.cmd_reset
      else              raise "Unknown command #{name}"
      end

      puts " => #{"✔".colorize.green}"
    end

    macro commands_regex_names
      "reset|vars|defs"
    end
  end

  def self.cmd_reset
    # TODO
    # VarStack.reset
    # @@cvars.clear
    # @@global.clear
    # @@consts.clear
    # @@program = Crystal::Program.new
    # @@main_visitor = nil
    # @@result = IC.nop
    # @@busy = false
    # @@code_lines = [""]
    # IC.run_file IC::PRELUDE_PATH
    # IC.underscore = IC.nil
  end
end
