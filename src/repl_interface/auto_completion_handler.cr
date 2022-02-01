module IC::ReplInterface
  # Handles the auto completion, this is done in four step:
  # 1) Retrieve the receiver code by reverse parsing the code from cursor position
  # 2) Determine the context (local vars, main_visitor, etc..)
  # 3) Search the method's name entries given a context and a receiver
  # 4) Display of these entries.
  class AutoCompletionHandler
    record AutoCompletionContext,
      local_vars : Crystal::Repl::LocalVars,
      program : Crystal::Program,
      main_visitor : Crystal::MainVisitor,
      interpreter : Crystal::Repl::Interpreter,
      special_commands : Array(String)

    @context : AutoCompletionContext? = nil

    # Store the previous display height in order properly clear the screen:
    @previous_completion_display_height : Int32? = nil

    # [1] Parses the receiver code:
    # TODO: currently we are only able to parse simple receiver e.g `foo.bar.bar`.
    def parse_receiver_code(expression_before_word_on_cursor) : String?
      expr = expression_before_word_on_cursor

      if expr && expr.starts_with?('.') && !expr.starts_with?("..")
        # If expression starts with '.' we want auto-complete from the last result ('__').
        receiver = "__"
      else
        # Get previous words while they are chained by '.'
        receiver_begin = expr.size
        pos = {receiver_begin - 1, 0}.max
        while expr[pos]? == '.'
          receiver_begin, _ = word_bound(expr, x: receiver_begin - 2)

          pos = {receiver_begin - 1, 0}.max
          break if pos == 0
        end

        if receiver_begin != expr.size
          receiver = expr[receiver_begin..(expr.size - 2)]?
        end
      end
      receiver
    end

    WORD_DELIMITERS = /[ \n\t\+\-,@&\!\?%=<>*\/\\\[\]\(\)\{\}\|\.\~]/

    # [1]
    private def word_bound(expr, x)
      word_begin = expr.rindex(WORD_DELIMITERS, offset: {x - 1, 0}.max) || -1
      word_end = expr.index(WORD_DELIMITERS, offset: x) || expr.size

      {word_begin + 1, word_end - 1}
    end

    # [2] Determines the context from expression before word on cursor:
    # TODO: currently, it not depend of expression_before_word_on_cursor, so the context is
    # only the top level.
    def set_context(repl, expression_before_word_on_cursor)
      @context = AutoCompletionContext.new(
        local_vars: repl.@interpreter.local_vars,
        program: repl.program,
        main_visitor: repl.@main_visitor,
        interpreter: repl.@interpreter,
        special_commands: [] of String
      )
    end

    # [2] Sets the context directly (used by pry):
    def set_context(local_vars, program, main_visitor, interpreter, special_commands)
      @context = AutoCompletionContext.new(local_vars, program, main_visitor, interpreter, special_commands.sort)
    end

    # [3] Finds completion entries from the word on cursor, `@context` must be set before.
    def find_entries(receiver_code, word_on_cursor)
      if context = @context
        entries, receiver_name = internal_find_entries(receiver_code, context, word_on_cursor)
      else
        entries, receiver_name = [] of String, ""
      end

      replacement = entries.empty? ? nil : common_root(entries)
      {entries, receiver_name, replacement}
    end

    # [3]
    private def internal_find_entries(receiver_code, context, name) : {Array(String), String}
      results = [] of String

      if receiver_code && !receiver_code.empty?
        begin
          if 'A' <= receiver_code[0] <= 'Z' && receiver_code.index('.').nil?
            type_result = interpret(context, receiver_code)
            receiver_type = type_result.type
          else
            type_result = interpret(context, "typeof(#{receiver_code})")
            receiver_type = type_result.type.instance_type
          end
        rescue
          return {results, ""}
        end

        # Add defs from receiver_type:
        results += find_def_entries(receiver_type, name).sort

        # Add keyword methods (.is_a?, .nil?, ...):
        results += Highlighter::KEYWORD_METHODS.each.map(&.to_s).select(&.starts_with? name).to_a.sort
      else
        receiver_type = context.program

        # Add special command:
        results += context.special_commands.select(&.starts_with? name)

        # Add top-level vars:
        vars = context.local_vars.names_at_block_level_zero
        results += vars.each.reject(&.starts_with? '_').select(&.starts_with? name).to_a.sort

        # Add defs from receiver_type:
        results += find_def_entries(receiver_type, name).sort

        # Add keywords:
        keywords = Highlighter::KEYWORDS + Highlighter::TRUE_FALSE_NIL + Highlighter::SPECIAL_VALUES
        results += keywords.each.map(&.to_s).select(&.starts_with? name).to_a.sort

        # Add types:
        results += context.program.types.each_key.select(&.starts_with? name).to_a.sort
      end

      results.uniq!

      {results, receiver_type.to_s}
    end

    # [3]
    private def find_def_entries(type, name)
      results = [] of String

      # Add def names from type:
      type.defs.try &.each do |def_name, def_|
        if def_.any? &.def.visibility.public?
          # Avoid special methods e.g `__crystal_raise`, `__crystal_malloc`... :
          unless def_name.starts_with?('_') || def_name == "`"
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
        results += find_def_entries(parent, name)
      end

      results
    end

    # [3] Interprets the receiver code under a context, the result will be the type in which we can lookup entries.
    private def interpret(context, receiver_code)
      parser = Crystal::Parser.new(
        receiver_code,
        string_pool: context.program.string_pool,
        var_scopes: [context.local_vars.names_at_block_level_zero.to_set]
      )
      node = parser.parse
      node = context.program.normalize(node)
      node = context.program.semantic(node, main_visitor: context.main_visitor)
      result = context.interpreter.interpret(node, context.main_visitor.meta_vars)
      context.main_visitor.clean
      result
    end

    # [3] Finds the common root text between given entries.
    private def common_root(entries)
      return "" if entries.empty?
      return entries[0] if entries.size == 1

      i = 0
      entry_iterators = entries.map &.each_char

      loop do
        char_on_first_entry = entries[0][i]?
        same = entry_iterators.all? do |entry|
          entry.next == char_on_first_entry
        end
        i += 1
        break if !same
      end
      entries[0][...(i - 1)]
    end

    # [4] Displays completion entries by columns, in a way that takes the less height possible:
    def display_entries(entries, receiver_name, expression_height, color? = true)
      # Compute the max number of row in a way to never take more than 3/4 of the screen.
      max_nb_row = (Term::Size.height - expression_height)*3//4 - 1
      return if max_nb_row <= 1
      return if entries.size <= 1

      # Print receiver type name:
      print receiver_name.colorize(:blue).underline.toggle(color?)
      puts ":"

      nb_rows = compute_nb_row(entries, max_nb_row)

      columns = entries.in_groups_of(nb_rows, "")
      column_widths = columns.map &.max_of &.size.+(2)

      nb_rows.times do |r|
        width = 0
        columns.each_with_index do |col, c|
          entry = col[r]
          col_width = column_widths[c]

          # As we doesn't known the nb of column to display, stop when column overflow the term width:
          width += col_width
          break if width > Term::Size.width

          # Display `...` on the last column and row:
          if r == nb_rows - 1 && (next_col_width = column_widths[c + 1]?) && width + next_col_width > Term::Size.width
            entry = "..."
          end

          # Display entry:
          print Highlighter.highlight(entry.ljust(col_width), toggle: color?)
        end
        puts
      end

      @previous_completion_display_height = nb_rows + 1
    end

    # [4]
    def clear_previous_display
      print Term::Cursor.clear_line_after

      if height = @previous_completion_display_height
        print Term::Cursor.up(height)
        print Term::Cursor.clear_screen_down

        @previous_completion_display_height = nil
      end
    end

    # [4] Computes the min number of rows required to display entries:
    # * if all entries cannot fit in `max_nb_row` rows, returns `max_nb_row`,
    # * if there are less than 10 entries, returns `entries.size` because in this case, it's more convenient to display them in one column.
    private def compute_nb_row(entries, max_nb_row)
      if entries.size > 10
        # test possible nb rows: (1 to max_nb_row)
        1.to max_nb_row do |r|
          width = 0
          # Sum the width of each given column:
          entries.each_slice(r, reuse: true) do |col|
            width += col.max_of &.size + 2
          end

          # If width fit width terminal, we found min row required:
          return r if width < Term::Size.width
        end
      end

      {entries.size, max_nb_row}.min
    end
  end
end
