# Adds a `control_nest` variable on the Crystal parser in order
# to track nesting of more expressions:
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

  # TODO: lib, macro, union
  {% for parse_method in %w(case begin unless while until select
                           parenthesized_expression empty_array_literal array_literal
                           percent_macro_control annotation enum_def) %}
    def parse_{{parse_method.id}}
      @control_nest += 1
      ret = previous_def
      @control_nest -= 1
      ret
    end
  {% end %}
end