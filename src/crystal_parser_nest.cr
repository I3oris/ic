# Adds a `control_nest` variable on the Crystal parser in order
# to track nesting of more expressions:
class Crystal::Parser
  getter control_nest = 0
  getter case_nest = 0

  def parse_case
    @case_nest += 1
    ret = previous_def
    @case_nest -= 1
    ret
  end

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

  def parse_block(block, stop_on_do = false)
    @control_nest += 1
    ret = previous_def
    @control_nest -= 1
    ret
  end

  def parse_call_args(stop_on_do_after_space = false, allow_curly = false, control = false)
    paren = @token.type.op_lparen?

    @control_nest += 1 if paren
    ret = previous_def
    @control_nest -= 1 if paren
    ret
  end

  # TODO: lib, macro, union
  {% for parse_method in %w(begin unless while until select
                           parenthesized_expression empty_array_literal array_literal
                           percent_macro_control annotation enum_def fun_literal) %}
    def parse_{{parse_method.id}}
      @control_nest += 1
      ret = previous_def
      @control_nest -= 1
      ret
    end
  {% end %}
end
