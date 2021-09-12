require "./repl_interface/multiline_input"

module IC
  class CrystalMultilineInput < REPLInterface::MultilineInput
    def initialize
      super
      self.prompt do |line_number, status|
        String.build do |io|
          io << "ic(#{Crystal::VERSION}):"
          io << sprintf("%03d", line_number).colorize.magenta
          case status
          when :multiline then io << "* "
          else                 io << "> "
          end
        end
      end

      self.formate do |expr|
        Crystal.format(expr)
      end

      self.highlight do |expr|
        Highlighter.highlight(expr)
      end

      self.multiline? do |expr|
        Crystal::Parser.parse(expr)
        false
      rescue e : Crystal::CodeError
        e.unterminated? ? true : false
      end

      self.indentation do |expr|
        parser = Crystal::Parser.new(expr)
        begin
          parser.parse
        rescue
        end

        parser.type_nest + parser.def_nest + parser.fun_nest + parser.control_nest
      end

      self.closing_keyword = %w(end \) ] })
      self.unindent_keyword = %w(else elsif when in rescue ensure)
    end
  end
end

# Track nesting of more expressions:
class Crystal::Parser
  getter control_nest = 0

  def parse_if(check_end = true)
    @control_nest += 1 if check_end
    ret = previous_def
    @control_nest -= 1 if check_end
    ret
  end

  def parse_hash_or_tuple_literal(allow_of = true)
    @control_nest += 1
    ret = previous_def
    @control_nest -= 1
    ret
  end

  def parse_var_or_call(global = false, force_call = false)
    @control_nest += 1
    ret = previous_def
    @control_nest -= 1
    ret
  end

  # def parse_block(block, stop_on_do = false)
  #   @control_nest += 1
  #   ret = previous_def
  #   @control_nest -= 1
  #   ret
  # end

  # lib macro union
  {% for parse_method in %w(case begin unless while until select
                           parenthesized_expression empty_array_literal array_literal
                           percent_macro_control annotation enum_def) %} #atomic_with_method
    def parse_{{parse_method.id}}
      @control_nest += 1
      ret = previous_def
      @control_nest -= 1
      ret
    end
  {% end %}
end
