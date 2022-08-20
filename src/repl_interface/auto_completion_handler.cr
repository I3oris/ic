require "../crystal_state"

module IC::ReplInterface
  # Handles auto completion.
  # Provides following important methods:
  #
  # * `set_context`: Sets an execution context on auto-completion.
  # Allow the handler to know program types, methods and local vars.
  #
  # * `complete_on`: Trigger the auto-completion given a *word_on_cursor* and expression before.
  # Stores the list of entries, and returns the *replacement* string.
  #
  # * `display_entries`: Displays on screen the stored entries.
  # Highlight the one selected. (initially `nil`).
  #
  # * `selection_next`/`selection_previous`: Increases/decrease the selected entry.
  #
  # * `open`/`close`: Toggle display, clear entries if close.
  #
  # * `clear`: Like `close`, but display a empty space instead of nothing.
  class AutoCompletionHandler
    record AutoCompletionContext,
      local_vars : Crystal::Repl::LocalVars,
      program : Crystal::Program,
      main_visitor : Crystal::MainVisitor,
      special_commands : Array(String)

    @context : AutoCompletionContext? = nil

    # Store the previous display height in order to properly clear the screen:
    @previous_completion_display_height : Int32? = nil
    @scope_name = ""
    @selection_pos : Int32? = nil
    getter entries = [] of String
    getter? open = false
    getter? cleared = false

    # Determines the context from a Repl
    def set_context(repl)
      @context = AutoCompletionContext.new(
        local_vars: repl.@interpreter.local_vars,
        program: repl.program,
        main_visitor: repl.@main_visitor,
        special_commands: [] of String
      )
    end

    # Sets the context directly (used by pry)
    def set_context(local_vars, program, main_visitor, special_commands)
      @context = AutoCompletionContext.new(local_vars, program, main_visitor, special_commands.sort)
    end

    # Triggers the auto-completion and returns a *replacement* string.
    # *word_on_cursor* correspond to call name to complete.
    # *expression_before_word_on_cursor* allow context to found the receiver type in which lookup auto-completion entries
    #
    # Stores the `entries` found.
    # returns *replacement* that correspond to the greatest common root of founds entries.
    # return *nil* is no entry found.
    def complete_on(word_on_cursor : String, expression_before_word_on_cursor : String) : String?
      receiver, scope = semantics(expression_before_word_on_cursor)

      find_entries(receiver, scope, word_on_cursor)
    end

    # Execute the semantics on *expression_before_word_on_cursor*:
    # Returns receiver AST if any, and the context type.
    private def semantics(expression_before_word_on_cursor) : {Crystal::ASTNode?, Crystal::Type?}
      context = @context || return nil, nil
      program = context.program

      if expression_before_word_on_cursor.ends_with?("require ")
        return Crystal::Require.new(""), program
      elsif expression_before_word_on_cursor.ends_with?("::")
        return nil, program
      end

      # Add a fictitious call "__auto_completion_call__" in place of
      # auto-completed call, so we can easily found what is the receiver after the parsing
      expr = expression_before_word_on_cursor
      expr += "__auto_completion_call__"

      # Terminate incomplete expressions with missing 'end's
      expr += missing_ends(expr)

      # Save the program state
      state = program.state

      # Create a temporary `Any` type that implements all types (like `NoReturn`)
      # This type is assigned to any unknown type in a def, and bypass some semantics checks (see `AnyType`).
      program.types["Any"] = AnyType.new program, program, "Any", nil

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

      if surrounding_def
        # We are in a Def which is not instantiated, so it have been ignored. Compute then the semantics inside it:
        receiver = semantics_on_def(surrounding_def, program, main_visitor, scope)
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

    # Computes semantics inside a Def.
    #
    # To do so, we should instantiate the Def with a fictitious `Call` constructed from args signature.
    # e.g.
    # ```
    # def foo(x, y : String, z = 0)
    #   ...
    # ```
    # is instantiated with:
    # foo(<Any>, <String>, <typeof(0)>)
    # with `<Type>` being a fictitious `ASTNode` with type `Type`.
    # `Any` is a special type to represented unknown arg instantiation.
    #
    # `*splat` are instantiated with one value, with type `Tuple(ArgumentType)`.
    # `**double_splat` are instantiated with no value, with type the empty `NamedTuple()`.
    #
    # TODO: block instantiation
    # TODO: free vars
    # TODO: class methods
    # TODO: make it work in Generics
    private def semantics_on_def(a_def, program, main_visitor, scope) : Crystal::ASTNode?
      args = [] of Crystal::ASTNode
      arg_types = [] of Crystal::Type
      named_args = [] of Crystal::NamedArgument
      named_args_types = [] of Crystal::NamedArgumentType

      # MainVisitor for arguments
      arg_main_visitor = Crystal::MainVisitor.new(program, main_visitor.vars, main_visitor.@typed_def, main_visitor.meta_vars)
      arg_main_visitor.scope = scope
      arg_main_visitor.path_lookup = scope

      a_def.args.each_with_index do |a, i|
        arg_type = argument_type(a, program, arg_main_visitor)
        if a_def.splat_index.try &.< i
          # Argument after splat need to be instantiated with named arg:
          named_args_types << Crystal::NamedArgumentType.new(a.external_name, arg_type)
          named_args << Crystal::NamedArgument.new(a.external_name, Crystal::Nop.new).tap(&.type = arg_type)
        else
          arg_types << arg_type
          args << Crystal::Nop.new.tap(&.type = arg_type)
        end
      end

      # Create the fictitious Call with typed args.
      call = Crystal::Call.new(nil, a_def.name, args, named_args: named_args)
      call.parent_visitor = main_visitor
      call.scope = scope

      # Instantiate the Call, gives back a typed `Def` ready to semantics.
      typed_defs = call.lookup_matches_in(scope, arg_types, named_args_types, nil, a_def.name, search_in_parents: false)

      if typed_def = typed_defs[0]? # TODO: we guess there is only one typed def for our Call, what append on dispatch?
        main_visitor = Crystal::MainVisitor.new(
          program,
          vars: typed_def.vars || Crystal::MetaVars.new,
          typed_def: typed_def)
        main_visitor.scope = scope
        main_visitor.path_lookup = scope

        # Execute the semantics on def body:
        begin
          ast = program.semantic(a_def.body, main_visitor: main_visitor)
        rescue
        end

        # Retrieve again the receiver node (now typed inside the def)
        visitor = GetAutoCompletionReceiverVisitor.new
        ast.try &.accept(visitor)
        return visitor.receiver
      end
    end

    # Gets `Crystal::Type` from `ASTNode` in a context of argument.
    private def argument_type(argument, program, main_visitor)
      if restriction = argument.restriction
        ast = program.semantic(restriction, main_visitor: main_visitor)
        ast.type.instance_type
      elsif value = argument.default_value
        ast = program.semantic(value, main_visitor: main_visitor)
        ast.type
      else
        program.types["Any"]
      end
    rescue
      program.types["Any"]
    end

    # Returns missing 'end's of an expression in order to parse it.
    private def missing_ends(expr) : String
      lexer = Crystal::Lexer.new(expr)

      delimiter_stack = [] of Symbol
      state = :normal

      previous_noblank_token_kind = nil
      token = lexer.next_token
      loop do
        case token.type
        when .eof?
          break
        when .op_lparen?
          delimiter_stack.push :"("
        when .op_lsquare?
          delimiter_stack.push :"["
        when .op_lcurly?
          delimiter_stack.push :"{"
        when .op_rparen?, .op_rsquare?, .op_rcurly?
          delimiter = delimiter_stack.pop?
          state = :string if delimiter == :interpolation
        when .ident?
          if token.value.in? %i(if unless)
            if is_suffix_if?(previous_noblank_token_kind)
              # nothing: suffix if should not be ended.
            else
              delimiter_stack.push :begin
            end
          elsif token.value == :class
            delimiter_stack.push :begin unless previous_noblank_token_kind == Crystal::Token::Kind::OP_PERIOD
          elsif token.value.in? %i(begin module struct def while until case do annotation lib)
            delimiter_stack.push :begin
          elsif token.value == :end
            delimiter_stack.pop?
          end
        when .delimiter_start?
          state = :string
          delimiter_stack.push :string
        when .delimiter_end?
          state = :normal
          delimiter_stack.pop
        when .interpolation_start?
          state = :interpolation
          delimiter_stack.push :interpolation
        end

        previous_noblank_token_kind = token.type unless token.type.space?
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

    private def is_suffix_if?(previous_token_kind)
      kind = previous_token_kind
      return false if kind.nil?

      kind.ident? || kind.number? || kind.symbol? || kind.const? || kind.delimiter_end? ||
        kind.op_rparen? || kind.op_rcurly? || kind.op_rsquare? || kind.op_percent_rcurly?
    end

    # Finds completion entries matching *word_on_cursor*, on *receiver* type, within a *scope*.
    private def find_entries(receiver, scope, word_on_cursor)
      if receiver.is_a? Crystal::Require
        find_require_entries(word_on_cursor)
      else
        names = word_on_cursor.split("::", remove_empty: false)
        if names.size >= 2
          find_const_entries(scope, names)
        else
          find_def_entries(receiver, scope, word_on_cursor)
        end
      end

      return @entries.empty? ? nil : common_root(@entries)
    end

    private def find_def_entries(receiver, scope, name)
      @entries.clear
      @scope_name = ""

      if receiver
        scope = receiver_type = receiver.type rescue return

        # Add methods from receiver_type:
        @entries += find_entries_on_type(receiver_type, name).sort

        # Add keyword methods (.is_a?, .nil?, ...):
        @entries += Highlighter::KEYWORD_METHODS.each.map(&.to_s).select(&.starts_with? name).to_a.sort
        @scope_name = receiver_type.to_s
      else
        context = @context || return

        scope ||= context.program

        # Add special command:
        @entries += context.special_commands.select(&.starts_with? name)

        # Add top-level vars:
        vars = context.local_vars.names_at_block_level_zero
        @entries += vars.each.reject(&.starts_with? '_').select(&.starts_with? name).to_a.sort

        # Add methods from receiver_type:
        @entries += find_entries_on_type(scope.metaclass, name).sort

        # Add keywords:
        keywords = Highlighter::KEYWORDS + Highlighter::TRUE_FALSE_NIL + Highlighter::SPECIAL_VALUES
        @entries += keywords.each.map(&.to_s).select(&.starts_with? name).to_a.sort

        # Add types:
        if types = scope.types?
          @entries += types.each_key.select(&.starts_with? name).to_a.sort
        end
        @scope_name = scope.to_s
      end

      @entries.uniq!
    end

    private def find_entries_on_type(type, name)
      results = [] of String

      # Add methods names from type:
      type.defs.try &.each
        .select do |def_name, defs|
          defs.any?(&.def.visibility.public?) &&
            def_name.starts_with? name
        end
        .reject do |def_name, _|
          def_name.starts_with?('_') || def_name == "`" ||           # Avoid special methods e.g `__crystal_raise`, `__crystal_malloc`...
            Highlighter::OPERATORS.any? { |op| op.to_s == def_name } # Avoid operators methods. TODO: allow them?
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

      # Recursively add methods names from parents:
      type.parents.try &.each do |parent|
        results += find_entries_on_type(parent, name)
      end

      results
    end

    private def find_require_entries(name)
      name = name.strip('"')

      if context = @context
        already_required = context.program.requires
      else
        already_required = Set(String).new
      end

      @entries.clear
      Crystal::CrystalPath.default_paths.each do |path|
        if File.exists?(path)
          Dir.each_child(path) do |file|
            if file.ends_with?(".cr") && file.starts_with?(name)
              unless Path[path, file].normalize.to_s.in? already_required
                require_name = file.chomp(".cr")
                @entries << %("#{require_name}")
              end
            end
          end
        end
      end

      @entries.sort!
      @scope_name = "require"
    end

    private def find_const_entries(scope, names)
      @entries.clear
      @scope_name = ""

      namespaces, name = names[...-1], names[-1]
      if scope
        full_scope = scope.lookup_path(namespaces, include_private: true)
        return if full_scope.is_a? Crystal::ASTNode # TODO: Foo(42)::Bar is not handled yet.

        if full_scope && (types = full_scope.types?)
          @entries = types.compact_map do |const_name, type|
            if !type.private? && const_name.starts_with?(name)
              "#{namespaces.join("::")}::#{const_name}"
            end
          end.uniq!.sort!
          @scope_name = full_scope.to_s
        end
      end
    end

    # Finds the common root text between given entries.
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

    # If open, displays completion entries by columns, minimizing the height.
    # Highlight the selected entry (initially `nil`).
    #
    # If cleared, displays `clear_size` space.
    #
    # If closed, do nothing.
    #
    # Returns the actual displayed height.
    def display_entries(io, color? = true, max_height = 10, clear_size = 0) : Int32
      if cleared?
        clear_size.times { io.puts }
        return clear_size
      end

      return 0 unless open?

      return 0 if max_height <= 1
      return 0 if @entries.size <= 1

      height = 0

      # Print scope type name:
      io.print @scope_name.colorize(:blue).underline.toggle(color?)
      io.puts ":"
      height += 1

      nb_rows = compute_nb_row(@entries, max_nb_row: max_height - height)

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
          entry_str = entry.ljust(col_width)

          # Colorize selection
          if r + c*nb_rows == @selection_pos
            if color?
              entry_str = entry_str.colorize.bright.on_dark_gray
            else
              entry_str = ">" + entry_str[...-1] # if no color, remove last spaces to let place to '*'.
            end
          end
          io.print entry_str
        end
        io.print Term::Cursor.clear_line_after if color?
        io.puts
      end

      height += nb_rows
      height
    end

    # Increases selected entry.
    def selection_next
      return nil if @entries.empty?

      if (pos = @selection_pos).nil?
        new_pos = 0
      else
        new_pos = (pos + 1) % @entries.size
      end
      @selection_pos = new_pos
      @entries[new_pos]
    end

    # Decreases selected entry.
    def selection_previous
      return nil if @entries.empty?

      if (pos = @selection_pos).nil?
        new_pos = 0
      else
        new_pos = (pos - 1) % @entries.size
      end
      @selection_pos = new_pos
      @entries[new_pos]
    end

    def open
      @open = true
      @cleared = false
    end

    def close
      @selection_pos = nil
      @entries.clear
      @open = false
      @cleared = false
    end

    def clear
      close
      @cleared = true
    end

    private def nb_cols_hold_in_term_width(column_widths)
      nb_cols = 0
      width = 0
      column_widths.each do |col_width|
        width += col_width
        break if width > self.term_width
        nb_cols += 1
      end
      nb_cols
    end

    # Computes the min number of rows required to display entries:
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
          return r if width < self.term_width
        end
      end

      {entries.size, max_nb_row}.min
    end

    private def term_width
      Term::Size.width
    end
  end

  # Search for the auto-completion call, in found its receiver, its surrounding def if any, and its scope.
  private class GetAutoCompletionReceiverVisitor < Crystal::Visitor
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

  # Special Type used when executing the semantics on auto-completion def.
  # It bypass the semantics checks.
  private class AnyType < ::Crystal::NonGenericClassType
    # implements all other types. (like NoReturn)
    def implements?(other_type)
      true
    end
  end
end

# [Monkey Patch]
# 1) Skip the `_auto_completion_call_` while executing semantic stage.
# 2) If any call argument is a `Any` type, skip that call and set the type to `Any`.
# this allows the auto-completion works after a `Any`:
# ```
# def foo(x)
#   x.to_s # would have raised "Error: undefined method 'to_s' for Any"
#
#   42.t| # ok
# ```
class Crystal::MainVisitor < Crystal::SemanticVisitor
  # Count if we are in a Call
  @call_nest = 0

  private class AnyTypeByPass < Exception
  end

  def visit(node : Call)
    @call_nest += 1
    if node.name == "__auto_completion_call__"
      # Skip the `_auto_completion_call_`
      node.set_type(@program.types["Any"])
      true
    else
      # Or does the normal behavior
      previous_def
    end
  rescue AnyTypeByPass
    # If any argument or obj was Any, we jump here
    node.set_type(@program.types["Any"])
    true
  ensure
    @call_nest -= 1
  end

  def end_visit(node)
    if @call_nest != 0 && (type = node.@type) && type == @program.types["Any"]?
      # `Any` in a Call, bypass the semantics
      raise AnyTypeByPass.new
    else
      true
    end
  end
end
