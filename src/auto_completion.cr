module IC
  private def self.auto_complete(repl, receiver, name, context_code)
    results = [] of String

    if receiver && !receiver.empty?
      begin
        if 'A' <= receiver[0] <= 'Z' && receiver.index('.').nil?
          type_result = repl.run_next_code(receiver)
          context_type = type_result.type
        else
          type_result = repl.run_next_code("typeof(#{receiver})")
          context_type = type_result.type.instance_type
        end
      rescue
        return {"", results}
      end

      # Add defs from context_type:
      results += add_completion_defs(context_type, name).sort

      # Add keyword methods (.is_a?, .nil?, ...):
      results += Highlighter::KEYWORD_METHODS.each.map(&.to_s).select(&.starts_with? name).to_a.sort
    else
      context_type = repl.program

      # Add top-level vars:
      vars = repl.@interpreter.local_vars.names_at_block_level_zero
      results += vars.each.reject(&.starts_with? '_').select(&.starts_with? name).to_a.sort

      # Add defs from context_type:
      results += add_completion_defs(context_type, name).sort

      # Add keywords:
      keywords = Highlighter::KEYWORDS + Highlighter::TRUE_FALSE_NIL + Highlighter::SPECIAL_VALUES
      results += keywords.each.map(&.to_s).select(&.starts_with? name).to_a.sort

      # Add types:
      results += repl.program.types.each_key.select(&.starts_with? name).to_a.sort
    end

    results.uniq!

    repl.clean
    {context_type.to_s, results}
  end

  private def self.add_completion_defs(type, name)
    results = [] of String

    # Add def names from type:
    type.defs.try &.each do |def_name, def_|
      if def_.any? &.def.visibility.public?
        # Avoid special methods e.g `__crystal_raise`, `__crystal_malloc`...
        unless def_name.starts_with?('_')
          if def_name.starts_with? name
            # Avoid operators methods:
            if Highlighter::OPERATORS.none? { |operator| operator.to_s == def_name }
              results << def_name
            end
          end
        end
      end
    end

    # Recursively add def names from parents:
    type.parents.try &.each do |parent|
      results += add_completion_defs(parent, name)
    end

    results
  end
end
