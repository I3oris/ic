require "./crystal_state"

module IC
  class CrystalCompleter
    record AutoCompletionContext,
      local_vars : Crystal::Repl::LocalVars,
      program : Crystal::Program,
      main_visitor : Crystal::MainVisitor,
      special_commands : Array(String)

    @context : AutoCompletionContext? = nil
    @scope_name = ""

    KEYWORD = %w(
      abstract alias annotation asm begin break case class def do else elsif end ensure enum extend
      false for fun if in include instance_sizeof lib macro module next nil of offsetof out
      pointerof private protected require rescue return select self sizeof struct super then
      true type typeof uninitialized union unless until verbatim when while with yield
      __DIR__ __END_LINE__ __FILE__ __LINE__
    )

    KEYWORD_METHODS = %w(as as? is_a? nil? responds_to?)

    # A auto-completion entry
    record Entry, entry : String, order = 1

    # All entries found
    @entries = [] of Entry

    # The documentation associated with a auto-completion entry
    record EntryDocumentation, header : String, doc : String?, summary : String? = nil do
      def initialize(object : Crystal::Def | Crystal::Macro | Crystal::Type)
        @header = object.to_s.each_line.first
        @doc = object.doc
      end

      def initialize(object : {String, String})
        @header, @doc = object
      end

      def summary
        @summary || doc.each_line.first
      end

      def doc
        @doc || ":nodoc:"
      end

      def doc?
        @doc
      end
    end

    # Documentations for each entry
    @entries_docs = Hash(String, Array(EntryDocumentation)).new { |h, k| h[k] = [] of EntryDocumentation }

    # Determines the context from a Repl.
    # Allow the handler to know program types, methods and local vars.
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
    def complete_on(name_filter : String, expression_before_word_on_cursor : String) : Tuple(String, Array(String))
      receiver, scope = semantics(expression_before_word_on_cursor)

      find_entries(receiver, scope, name_filter)
      return @scope_name, @entries.map(&.entry)
    end

    # Gets the documentation for the given *entry*, if any
    def documentation(entry : String) : String?
      @entries_docs[entry]?.try do |objects|
        String.build do |io|
          io << "# #{entry}\n\n"
          io << "```\n"
          objects.uniq(&.header).each do |object|
            io << object.header << '\n'
          end
          io << "```\n"
          objects.each do |object|
            if doc = object.doc?
              io << "\n## `#{object.header}`\n" unless objects.size == 1
              io << doc
              io << "\n\n"
            end
          end
        end
      end
    end

    # Gets the documentation summary (one line) for the given *entry*, if any
    def documentation_summary(entry : String) : String?
      @entries_docs[entry]?.try do |object|
        object.first.summary
      end
    end

    # Execute the semantics on *expression_before_word_on_cursor*:
    # Returns receiver AST if any, and the context type.
    private def semantics(expression_before_word_on_cursor) : {Crystal::ASTNode?, Crystal::Type?}
      context = @context || return nil, nil
      program = context.program
      program.wants_doc = true

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
      # TODO: Instead of save the state of program, modify the current program,
      # then try to restore the program to the saved state, which actually doesn't work well:
      # We can create a temporary program in which we import the types and definitions, then just discard it.

      # Create a temporary `Any` type that implements all types (like `NoReturn`)
      # This type is assigned to any unknown type in a def, and bypass some semantics checks (see `AnyType`).
      program.types["Any"] = AnyType.new program, program, "Any", nil

      # Now the expression is complete, parse it within the context
      parser = Crystal::Parser.new(
        expr,
        string_pool: program.string_pool,
        var_scopes: [context.local_vars.names_at_block_level_zero.to_set],
      )
      parser.wants_doc = true
      ast = parser.parse
      ast = program.normalize(ast)

      # Copy the main visitor of the context
      main_visitor = context.main_visitor
      main_visitor = Crystal::MainVisitor.new(program, main_visitor.vars.clone, main_visitor.@typed_def, main_visitor.meta_vars.clone)
      main_visitor.scope = main_visitor.@scope
      main_visitor.path_lookup = main_visitor.path_lookup

      # Execute the semantics on the full ast node to compute all types.
      begin
        ast = program.semantic(ast, main_visitor: main_visitor, cleanup: false)
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

      # If receiver have still no type, we try to execute the semantic only on it:
      # This happen with ArrayLiteral (e.g. `[x.`).
      #
      # NOTE:
      # This is not needed if we executing the cleanup phase, but since 1.6.0 we have to skip the cleanup phase. (otherwise all the auto-completion broke up!)
      if receiver && !receiver.type?
        program.visit_main(receiver, visitor: main_visitor, cleanup: false)
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
          ast = program.visit_main(a_def.body, visitor: main_visitor, cleanup: false)
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
          case token.value
          when Char, String, Nil
            # nothing
          when .if?, .unless?
            if suffix_if?(previous_noblank_token_kind)
              # nothing: suffix if should not be ended.
            else
              delimiter_stack.push :begin
            end
          when .class?
            unless previous_noblank_token_kind == Crystal::Token::Kind::OP_PERIOD
              delimiter_stack.push :begin
            end
          when .begin?, .module?, .struct?, .def?, .while?, .until?, .case?, .do?, .annotation?, .lib?
            delimiter_stack.push :begin
          when .end?
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

    private def suffix_if?(previous_token_kind)
      kind = previous_token_kind
      return false if kind.nil?

      kind.ident? || kind.number? || kind.symbol? || kind.const? || kind.delimiter_end? ||
        kind.op_rparen? || kind.op_rcurly? || kind.op_rsquare? || kind.op_percent_rcurly?
    end

    private def add_entry(entry : String, object = nil, order = 1)
      @entries << Entry.new(entry, order)
      @entries_docs[entry] << EntryDocumentation.new(object) if object
    end

    private def add_entry(entry : String, objects : Array, order = 1)
      @entries << Entry.new(entry, order)
      objects.each { |object| @entries_docs[entry] << EntryDocumentation.new(object) }
    end

    private def add_entries(entries, order = 1, &)
      entries.each do |entry|
        add_entry(entry, yield(entry), order)
      end
    end

    # Finds completion entries matching *word_on_cursor*, on *receiver* type, within a *scope*.
    private def find_entries(receiver, scope, word_on_cursor)
      @entries.clear
      @entries_docs.clear

      if receiver.is_a? Crystal::Require
        find_require_entries(word_on_cursor)
      else
        names = word_on_cursor.split("::", remove_empty: false)
        if names.size >= 2
          find_const_entries(scope, names)
        else
          find_def_entries(receiver, scope)
        end
      end
      @entries.sort! do |a, b|
        a.order == b.order ? a.entry <=> b.entry : a.order <=> b.order
      end.uniq! &.entry
    end

    private def find_def_entries(receiver, scope)
      @scope_name = ""

      if receiver
        scope = receiver_type = receiver.type rescue return

        # Add methods from receiver_type:
        find_entries_on_type(receiver_type) # order: 3

        # Add keyword methods (.is_a?, .nil?, ...):
        add_entries(KEYWORD_METHODS, order: 4) { |e| {e, "Pseudo method #{e}"} }
        @scope_name = receiver_type.to_s
      else
        context = @context || return

        scope ||= context.program

        # Add special command:
        add_entries(context.special_commands, order: 1) { |e| {e, "Command"} }

        # Add top-level vars:
        vars = context.local_vars.names_at_block_level_zero
        add_entries(vars.reject(&.starts_with? '_'), order: 2) { |e| {e, "Local variable #{e}"} }

        # Add methods from receiver_type:
        find_entries_on_type(scope.metaclass) # order: 3

        # Add keywords:
        add_entries(KEYWORD, order: 4) { |e| {e, "#{e.titleize} keyword"} }

        # Add types:
        if types = scope.types?
          types.each do |type_name, type|
            add_entry(type_name, type, order: 5) # 5
          end
        end

        @scope_name = scope.to_s
      end
    end

    private def find_entries_on_type(type)
      # Add methods names from type:
      type.defs.try &.each
        .select do |_def_name, defs|
          defs.any?(&.def.visibility.public?)
        end
        .reject do |def_name, _|
          def_name.starts_with?('_') || def_name == "`" ||           # Avoid special methods e.g `__crystal_raise`, `__crystal_malloc`...
            Highlighter::OPERATORS.any? { |op| op.to_s == def_name } # Avoid operators methods. TODO: allow them?
        end
        .each do |def_name, defs|
          add_entry(def_name, defs.map(&.def), order: 3)
        end

      # Add macro names from type:
      type.macros.try &.each
        .select do |_macro_name, macros|
          macros.any?(&.visibility.public?)
        end
        .each do |macro_name, macros|
          add_entry(macro_name, macros, order: 3)
        end

      # Recursively add methods names from parents:
      type.parents.try &.each do |parent|
        find_entries_on_type(parent)
      end
    end

    private def find_require_entries(name)
      name = name.strip('"')
      # TODO re-enable this:
      # @name_filter = %("#{name}) # allow to auto-complete when `require jso` is written. (name_filter = `"jso` instead of `jso`)

      if context = @context
        already_required = context.program.requires
      else
        already_required = Set(String).new
      end

      Crystal::CrystalPath.default_paths.each do |path|
        if File.exists?(path)
          Dir.each_child(path) do |file|
            if file.ends_with?(".cr") && file.starts_with?(name)
              unless Path[path, file].normalize.to_s.in? already_required
                require_name = file.chomp(".cr")
                add_entry(%("#{require_name}"))
              end
            end
          end
        end
      end

      @scope_name = "require"
    end

    private def find_const_entries(scope, names)
      @scope_name = ""

      namespaces, name = names[...-1], names[-1]
      if scope
        full_scope = scope.lookup_path(namespaces, include_private: true)
        return if full_scope.is_a? Crystal::ASTNode # TODO: Foo(42)::Bar is not handled yet.

        if full_scope && (types = full_scope.types?)
          types.each do |const_name, type|
            if !type.private? && const_name.starts_with?(name)
              entry = "#{namespaces.join("::")}::#{const_name}"
              add_entry(entry, type, order: 1)
            end
          end

          @scope_name = full_scope.to_s
        end
      end
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
