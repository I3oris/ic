require "./crystal_state"

module IC::ReplInterface
  # Handles the auto completion, this is done in five step:
  # 1) Retrieve an parse the receiver code of the auto completed method call
  # 2) Execute the semantic on the parsed node
  # 3) Determine the context (local vars, main_visitor, etc..)
  # 4) Search the method's name entries given a context and a receiver
  # 5) Display of these entries.
  class AutoCompletionHandler
    record AutoCompletionContext,
      local_vars : Crystal::Repl::LocalVars,
      program : Crystal::Program,
      main_visitor : Crystal::MainVisitor,
      special_commands : Array(String)

    @context : AutoCompletionContext? = nil

    # Store the previous display height in order to properly clear the screen:
    @previous_completion_display_height : Int32? = nil
    @entries = [] of String
    @scope_name = ""
    @selection_pos : Int32? = nil
    getter? open = false

    # [1+2] Parses the receiver code:
    # Returns receiver AST if any, and the context type.
    def parse_receiver_code(expression_before_word_on_cursor) : {Crystal::ASTNode?, Crystal::Type?}
      context = @context || return nil, nil
      program = context.program

      if expression_before_word_on_cursor.ends_with? "require "
        return Crystal::Require.new(""), program
      end

      # Add a fictitious call "__auto_completion_call__" in place of
      # auto-completed call, so we can easily found what is the receiver after the parsing
      expr = expression_before_word_on_cursor
      expr += "__auto_completion_call__"

      # Terminate incomplete expressions with missing 'end's
      expr += missing_ends(expr)

      state = program.state

      # Now the expression is complete, parse it within the context
      parser = Crystal::Parser.new(
        expr,
        string_pool: program.string_pool,
        var_scopes: [context.local_vars.names_at_block_level_zero.to_set],
      )
      ast = parser.parse
      ast = program.normalize(ast)

      # Copy the main visitor of the context
      main_visitor = context.main_visitor
      main_visitor = Crystal::MainVisitor.new(program, main_visitor.vars.clone, main_visitor.@typed_def, main_visitor.meta_vars.clone)
      main_visitor.scope = main_visitor.@scope
      main_visitor.path_lookup = main_visitor.path_lookup

      # Execute the semantics on the full ast node to compute all types.
      begin
        ast = program.semantic(ast, main_visitor: main_visitor)
      rescue
      end

      # Retrieve the receiver node (now typed), and gets its scope.
      visitor = GetAutoCompletionReceiverVisitor.new
      ast.accept(visitor)
      receiver = visitor.receiver

      surrounding_def = visitor.surrounding_def
      scope = visitor.scope || program

      # Semantics step cannot compute the types inside a def, because the def is not instantiated.
      # So, to have auto-completion inside a def though, we execute semantics on the body only,
      # within the def scope.
      if surrounding_def
        gatherer = Crystal::Repl::LocalVarsGatherer.new(surrounding_def.location.not_nil!, surrounding_def)
        gatherer.gather

        main_visitor = Crystal::MainVisitor.new(
          program,
          vars: gatherer.meta_vars,
          meta_vars: gatherer.meta_vars,
          typed_def: context.main_visitor.@typed_def)
        main_visitor.scope = scope
        main_visitor.path_lookup = scope

        begin
          program.semantic(surrounding_def.body, main_visitor: main_visitor)
        rescue
        end
      end

      return receiver, scope
    rescue
      return nil, nil
    ensure
      if context
        context.main_visitor.clean
        context.program.state = state
      end
    end

    # [1] Returns missing 'end's of an expression in order to parse it.
    def missing_ends(expr) : String
      lexer = Crystal::Lexer.new(expr)

      delimiter_stack = [] of Symbol
      state = :normal

      token = lexer.next_token
      loop do
        case token.type
        when :EOF then break
        when :"(", :"[", :"{"
          delimiter_stack.push token.type
        when :")", :"]", :"}"
          delimiter = delimiter_stack.pop?
          state = :string if delimiter == :interpolation
        when :IDENT
          if token.value.in? %i(begin module class struct def if unless while until case do annotation lib)
            delimiter_stack.push :begin
          elsif token.value == :end
            delimiter_stack.pop?
          end
        when :DELIMITER_START
          state = :string
          delimiter_stack.push :string
        when :DELIMITER_END
          state = :normal
          delimiter_stack.pop
        when :INTERPOLATION_START
          state = :interpolation
          delimiter_stack.push :interpolation
        end

        if state == :string
          token = lexer.next_string_token(token.delimiter_state)
        else
          token = lexer.next_token
        end
      end

      String.build do |str|
        while delemiter = delimiter_stack.pop?
          case delemiter
          when :"("           then str << ')'
          when :"["           then str << ']'
          when :"{"           then str << '}'
          when :begin         then str << "; end"
          when :interpolation then str << '}'
          when :string        then str << '"'
          end
        end
      end
    end

    # [2] Determines the context from a Repl
    def set_context(repl)
      @context = AutoCompletionContext.new(
        local_vars: repl.@interpreter.local_vars,
        program: repl.program,
        main_visitor: repl.@main_visitor,
        special_commands: [] of String
      )
    end

    # [2] Sets the context directly (used by pry):
    def set_context(local_vars, program, main_visitor, special_commands)
      @context = AutoCompletionContext.new(local_vars, program, main_visitor, special_commands.sort)
    end

    # [4] Finds completion entries from the word on cursor, `set_context` must be called before.
    def find_entries(receiver, scope, word_on_cursor)
      if receiver.is_a? Crystal::Require
        internal_find_require_entries(word_on_cursor)
      else
        internal_find_entries(receiver, scope, word_on_cursor)
      end

      return @entries.empty? ? nil : common_root(@entries)
    end

    # [4]
    private def internal_find_entries(receiver, scope, name)
      @entries.clear
      @scope_name = ""

      if receiver
        scope = receiver_type = receiver.type rescue return

        # Add defs from receiver_type:
        @entries += find_def_entries(receiver_type, name).sort

        # Add keyword methods (.is_a?, .nil?, ...):
        @entries += Highlighter::KEYWORD_METHODS.each.map(&.to_s).select(&.starts_with? name).to_a.sort
      else
        context = @context || return

        scope ||= context.program

        # Add special command:
        @entries += context.special_commands.select(&.starts_with? name)

        # Add top-level vars:
        vars = context.local_vars.names_at_block_level_zero
        @entries += vars.each.reject(&.starts_with? '_').select(&.starts_with? name).to_a.sort

        # Add defs from receiver_type:
        @entries += find_def_entries(scope.metaclass, name).sort

        # Add keywords:
        keywords = Highlighter::KEYWORDS + Highlighter::TRUE_FALSE_NIL + Highlighter::SPECIAL_VALUES
        @entries += keywords.each.map(&.to_s).select(&.starts_with? name).to_a.sort

        # Add types:
        @entries += scope.types.each_key.select(&.starts_with? name).to_a.sort
      end

      @entries.uniq!
      @scope_name = scope.to_s
    end

    # [4]
    private def find_def_entries(type, name)
      results = [] of String

      # Add def names from type:
      type.defs.try &.each
        .select do |def_name, defs|
          defs.any?(&.def.visibility.public?) &&
            def_name.starts_with? name
        end
        .reject do |def_name, _|
          def_name.starts_with?('_') || def_name == "`" ||              # Avoid special methods e.g `__crystal_raise`, `__crystal_malloc`...
            Highlighter::OPERATORS.any? { |op| op.to_s == def_name } || # Avoid operators methods
            def_name.in? "[]", "[]=", "[]?"
        end
        .each do |def_name, _|
          results << def_name
        end

      # Add macro names from type:
      type.macros.try &.each
        .select do |macro_name, macros|
          macros.any?(&.visibility.public?) &&
            macro_name.starts_with? name
        end
        .each do |macro_name, _|
          results << macro_name
        end

      # Recursively add def names from parents:
      type.parents.try &.each do |parent|
        results += find_def_entries(parent, name)
      end

      results
    end

    # [4]
    def internal_find_require_entries(name)
      name = name.strip('"')

      if context = @context
        already_required = context.program.requires
      else
        already_required = Set(String).new
      end

      @entries.clear
      Crystal::CrystalPath.default_paths.each do |path|
        Dir.children(path).each do |file|
          if file.ends_with?(".cr") && file.starts_with?(name)
            unless Path[path, file].to_s.in? already_required
              require_name = file.chomp(".cr")
              @entries << %("#{require_name}")
            end
          end
        end
      end

      @entries.sort!
      @scope_name = "require"
    end

    # [4] Finds the common root text between given entries.
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

    # [5] Displays completion entries by columns, minimizing the height:
    def display_entries(expression_height, color? = true)
      clear_previous_display

      # Compute the max number of row in a way to never take more than 3/4 of the screen.
      max_nb_row = (Term::Size.height - expression_height)*3//4 - 1
      return if max_nb_row <= 1
      return if @entries.size <= 1

      # Print scope type name:
      print @scope_name.colorize(:blue).underline.toggle(color?)
      puts ":"

      nb_rows = compute_nb_row(@entries, max_nb_row)

      columns = @entries.in_groups_of(nb_rows, "")
      column_widths = columns.map &.max_of &.size.+(2)

      nb_cols = nb_cols_hold_in_term_width(column_widths)

      col_start = 0
      if pos = @selection_pos
        col_end = pos // nb_rows

        if col_end >= nb_cols
          nb_cols = nb_cols_hold_in_term_width(column_widths: column_widths[..col_end].reverse_each)

          col_start = col_end - nb_cols + 1
        end
      end

      nb_rows.times do |r|
        nb_cols.times do |c|
          c += col_start

          entry = columns[c][r]
          col_width = column_widths[c]

          # Display `...` on the last column and row:
          if (r == nb_rows - 1) && (c - col_start == nb_cols - 1) && columns[c + 1]?
            entry += ".."
          end

          # Display entry:
          # entry_str = Highlighter.highlight(entry.ljust(col_width), toggle: color?)
          entry_str = entry.ljust(col_width)

          # Colorize selection
          if r + c*nb_rows == @selection_pos
            entry_str = entry_str.colorize.toggle(color?).bright.on_dark_gray
          end
          print entry_str
        end
        print Term::Cursor.clear_line_after
        puts
      end

      # Store the height actually displayed, so we can clear it later
      @previous_completion_display_height = nb_rows + 1
      @open = true
    end

    def selection_next
      if (pos = @selection_pos).nil?
        new_pos = 0
      else
        new_pos = (pos + 1) % @entries.size
      end
      @selection_pos = new_pos
      @entries[new_pos]
    end

    def selection_previous
      if (pos = @selection_pos).nil?
        new_pos = 0
      else
        new_pos = (pos - 1) % @entries.size
      end
      @selection_pos = new_pos
      @entries[new_pos]
    end

    private def clear_previous_display
      print Term::Cursor.clear_line_after

      if height = @previous_completion_display_height
        print Term::Cursor.up(height)
        print Term::Cursor.clear_screen_down

        @previous_completion_display_height = nil
      end
    end

    def clear
      if open?
        prev_height = @previous_completion_display_height || 0
        clear_previous_display
        prev_height.times { puts }
        @previous_completion_display_height = prev_height

        @selection_pos = nil
        @entries.clear
        @open = false
      end
    end

    def close
      clear_previous_display
      @selection_pos = nil
      @entries.clear
      @open = false
    end

    private def nb_cols_hold_in_term_width(column_widths)
      nb_cols = 0
      width = 0
      column_widths.each do |col_width|
        width += col_width
        break if width > Term::Size.width
        nb_cols += 1
      end
      nb_cols
    end

    # [5] Computes the min number of rows required to display entries:
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

  # Search for the auto-completion call, in found its receiver, its surrounding def if any, and its scope.
  class GetAutoCompletionReceiverVisitor < Crystal::Visitor
    @found = false
    getter receiver : Crystal::ASTNode? = nil
    getter surrounding_def : Crystal::Def? = nil
    @scopes = [] of Crystal::Type

    def scope
      @scopes.last?
    end

    def visit(node)
      if node.is_a?(Crystal::Call) && node.name == "__auto_completion_call__"
        @found = true
        @receiver ||= node.obj
      end
      true
    end

    def visit(node : Crystal::Def)
      @surrounding_def = node unless @found
      true
    end

    def end_visit(node : Crystal::Def)
      @surrounding_def = nil unless @found
      true
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @scopes.push node.resolved_type unless @found
      true
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @scopes.pop? unless @found
      true
    end
  end
end
