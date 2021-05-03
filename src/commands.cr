module IC
  module Commands
    def self.run_cmd(name, args)
      puts
      case name
      when "reset" then IC.cmd_reset
      when "vars"  then IC.cmd_vars
      when "defs"  then IC.cmd_defs
      else              bug! "Unknown command #{name}"
      end

      puts " => #{"✔".colorize.green}"
    end

    macro commands_regex_names
      "reset|vars|defs"
    end
  end

  def self.cmd_reset
    VarStack.reset
    @@consts.clear
    @@program = Crystal::Program.new
    IC.run_file "./ic_prelude.cr"
    @@result = IC.nop
    @@busy = false
    IC.underscore = IC.nil
  end

  def self.cmd_vars
    VarStack.top_level_vars.each do |name, value|
      puts Highlighter.highlight(" #{name} : #{value.type.cr_type} = #{value.result}", no_invitation: true)
    end
    puts unless @@consts.empty?
    @@consts.each do |name, value|
      puts Highlighter.highlight(" #{name} : #{value.type.cr_type} = #{value.result}", no_invitation: true)
    end
  end

  def self.cmd_defs
    @@program.defs.try &.each do |key, defs|
      defs.each do |d|
        puts Highlighter.highlight(d.def.to_s, no_invitation: true)
        puts
      end
    end
  end
end
