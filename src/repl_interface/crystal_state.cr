class Crystal::Program
  # Save the state of a crystal program in a instant T
  # This is useful for two reasons:
  # * When an error is raised due to an invalid user code, we doesn't want to keep methods or
  #   variables defined inside the erroneous code.
  # * As the semantic is triggered on auto-completion, we doesn't want keep definitions while the user
  #  doesn't have validate the input.
  def state
    {
      @types.dup,
      @vars.dup,
      @defs.dup,
      @const_initializers.dup,
      @class_var_initializers.dup,
      self.literal_expander.state,
    }
  end

  # Restore the state
  # NOTE: Currently the restoration of the state is far to be perfect, but still remove
  # most of the extra definitions.
  def state=(state)
    return if state.nil?

    @types, @vars, @defs, @const_initializers, @class_var_initializers, self.literal_expander.state = state
  end
end

class Crystal::LiteralExpander
  def state
    @regexes.dup
  end

  def state=(@regexes)
  end
end
