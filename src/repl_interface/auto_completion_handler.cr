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

    # [1+2] Parses the receiver code:
    def parse_receiver_code(expression_before_word_on_cursor)
      context = @context || return nil

      # Add a fictitious call "__auto_completion_call__" in place of
      # auto-completed call, so we can easily found what is the receiver after the parsing
      expr = expression_before_word_on_cursor
      expr += "__auto_completion_call__" if expr.ends_with? '.'

      # Terminate incomplete expressions with missing 'end's
      expr += missing_ends(expr)

      state = context.program.state

      # Now the expression is complete, parse it within the context.
      parser = Crystal::Parser.new(
        expr,
        string_pool: context.program.string_pool,
        var_scopes: [context.local_vars.names_at_block_level_zero.to_set],
      )
      ast = parser.parse
      ast = context.program.normalize(ast)

      # transform the "__auto_completion_call__" AutoCompletionCall
      ast = ast.transform(AutoCompletionCallTransformer.new)

      begin
        ast = context.program.semantic(ast, main_visitor: context.main_visitor)
      rescue
      end

      visitor = GetAutoCompletionReceiverVisitor.new
      ast.accept(visitor)
      receiver = visitor.receiver

      # TODO: execute the semantic also on the body of the def surrounding the receiver

    rescue
      nil
    ensure
      if context
        context.main_visitor.clean
        context.program.state = state
      end
      receiver
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
    def find_entries(receiver, word_on_cursor)
      entries, receiver_name = internal_find_entries(receiver, word_on_cursor)

      replacement = entries.empty? ? nil : common_root(entries)
      {entries, receiver_name, replacement}
    end

    # [4]
    private def internal_find_entries(receiver, name) : {Array(String), String}
      results = [] of String

      if receiver
        receiver_type = receiver.type rescue return {results, ""}

        # Add defs from receiver_type:
        results += find_def_entries(receiver_type, name).sort

        # Add keyword methods (.is_a?, .nil?, ...):
        results += Highlighter::KEYWORD_METHODS.each.map(&.to_s).select(&.starts_with? name).to_a.sort
      else
        context = @context || return {results, ""}

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

    # [5]
    def clear_previous_display
      print Term::Cursor.clear_line_after

      if height = @previous_completion_display_height
        print Term::Cursor.up(height)
        print Term::Cursor.clear_screen_down

        @previous_completion_display_height = nil
      end
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

  class AutoCompletionCall < Crystal::Call
    def initialize(obj : Crystal::ASTNode?)
      super(obj, "__auto_completion_call__")
    end
  end

  # Transformer that retrieve the ASTnode receiver of an auto-completion (receiver of the call "__auto_completion_call__")
  # and mark it with a AutoCompletionCall node.
  class AutoCompletionCallTransformer < Crystal::Transformer
    def transform(node : Crystal::Call)
      if node.name == "__auto_completion_call__"
        # obj.location = Crystal::Location.new("__auto_completion_recevier_location__", 0, 0)
        # obj
        AutoCompletionCall.new(node.obj)
      else
        super node
      end
    end
  end

  class GetAutoCompletionReceiverVisitor < Crystal::Visitor
    getter receiver : Crystal::ASTNode? = nil

    # def visit(node)
    #   if node.location.try &.filename == "__auto_completion_recevier_location__"
    #     @receiver ||= node
    #   end
    #   true
    # end

    def visit(node)
      if node.is_a? AutoCompletionCall
        @receiver ||= node.obj
      end
      true
    end
  end
end
