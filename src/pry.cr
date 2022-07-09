require "./repl_interface/repl_interface"

class IC::PryInterface < IC::ReplInterface::ReplInterface
  def self.new
    new do |_, color?|
      "ic(#{Crystal::Config.version}):#{"pry".colorize(:magenta).toggle(color?)}> "
    end
  end

  def on_ctrl_up
    yield "whereami"
  end

  def on_ctrl_down
    yield "next"
  end

  def on_ctrl_left
    yield "finish"
  end

  def on_ctrl_right
    yield "step"
  end
end

# from compiler/crystal/interpreter/interpreter.cr: (1.3.0-dev)
class Crystal::Repl::Interpreter
  getter pry_interface = IC::PryInterface.new

  private def pry(ip, instructions, stack_bottom, stack)
    # We trigger keyboard interrupt here because only 'pry' can interrupt the running program.
    if @keyboard_interrupt
      @stack.clear
      @call_stack = [] of CallFrame
      @call_stack_leave_index = 0
      @block_level = 0
      @compiled_def = nil
      @keyboard_interrupt = false
      self.pry = false
      raise KeyboardInterrupt.new
    end

    # IC ADDING: (+ changed `print` to `output.print`)
    output = @pry_interface.output
    # END
    offset = (ip - instructions.instructions.to_unsafe).to_i32
    node = instructions.nodes[offset]?
    pry_node = @pry_node

    return unless node

    location = node.location
    return unless location

    return unless different_node_line?(node, pry_node)

    call_frame = @call_stack.last
    compiled_def = call_frame.compiled_def
    compiled_block = call_frame.compiled_block
    local_vars = compiled_block.try(&.local_vars) || compiled_def.local_vars

    a_def = compiled_def.def

    whereami(a_def, location)

    # puts
    # puts Slice.new(stack_bottom, stack - stack_bottom).hexdump
    # puts

    # Remember the portion from stack_bottom + local_vars.max_bytesize up to stack
    # because it might happen that the child interpreter will overwrite some
    # of that if we already have some values in the stack past the local vars
    data_size = stack - (stack_bottom + local_vars.max_bytesize)
    data = Pointer(Void).malloc(data_size).as(UInt8*)
    data.copy_from(stack_bottom + local_vars.max_bytesize, data_size)

    gatherer = LocalVarsGatherer.new(location, a_def)
    gatherer.gather
    meta_vars = gatherer.meta_vars
    block_level = local_vars.block_level
    owner = compiled_def.owner

    closure_context =
      if compiled_block
        compiled_block.closure_context
      else
        compiled_def.closure_context
      end

    closure_context.try &.vars.each do |name, (index, type)|
      meta_vars[name] = MetaVar.new(name, type)
    end

    main_visitor = MainVisitor.new(
      @context.program,
      vars: meta_vars,
      meta_vars: meta_vars,
      typed_def: a_def)

    # Scope is used for instance types, never for Program
    unless owner.is_a?(Program)
      main_visitor.scope = owner
    end

    main_visitor.path_lookup = owner

    interpreter = Interpreter.new(self, compiled_def, local_vars, closure_context, stack_bottom, block_level)

    # IC MODIFICATION:
    @pry_interface.color = @context.program.color?
    @pry_interface.auto_completion.set_context(
      local_vars: interpreter.local_vars,
      program: @context.program,
      main_visitor: main_visitor,
      special_commands: %w(continue step next finish whereami),
    )

    @pry_interface.run do |line|
    # WAS:
    # while @pry
    #   TODO: supoort multi-line expressions

    #   print "pry> "
    #   line = gets
    # END
      unless line
        self.pry = false
        break
      end

      case line
      when "continue"
        self.pry = false
        break
      when "step"
        @pry_node = node
        @pry_max_target_frame = nil
        break
      when "next"
        @pry_node = node
        @pry_max_target_frame = @call_stack.last.real_frame_index
        break
      when "finish"
        @pry_node = node
        @pry_max_target_frame = @call_stack.last.real_frame_index - 1
        break
      when "whereami"
        whereami(a_def, location)
        next
      when "*d"
        output.puts local_vars
        output.puts Disassembler.disassemble(@context, compiled_block || compiled_def)
        next
      when "*s"
        output.puts Slice.new(@stack, stack - @stack).hexdump
        next
      end

      begin
        parser = Parser.new(
          line,
          string_pool: @context.program.string_pool,
          var_scopes: [meta_vars.keys.to_set],
        )
        line_node = parser.parse

        line_node = @context.program.normalize(line_node)
        line_node = @context.program.semantic(line_node, main_visitor: main_visitor)

        value = interpreter.interpret(line_node, meta_vars)

        # IC MODIFICATION:
        output.puts " => #{IC::Highlighter.highlight(value.to_s, toggle: @context.program.color?)}"
        # WAS:
        # puts value.to_s
        # END
      rescue ex : EscapingException
        output.print "Unhandled exception: "
        output.print ex
      rescue ex : Crystal::CodeError
        # IC MODIFICATION:
        ex.color = @context.program.color?
        # WAS:
        # ex.color = true
        # END
        ex.error_trace = true
        output.puts ex
        next
      rescue ex : Exception
        ex.inspect_with_backtrace(STDOUT)
        next
      end
    end

    # Restore the stack data in case it tas overwritten
    (stack_bottom + local_vars.max_bytesize).copy_from(data, data_size)
  end

  private def whereami(a_def : Def, location : Location)
    filename = location.filename
    line_number = location.line_number
    column_number = location.column_number

    # IC ADDING:
    output = @pry_interface.output

    a_def_owner = @context.program.colorize(a_def.owner.to_s).blue.underline
    hashtag = @context.program.colorize("#").dark_gray.bold
    # END

    if filename.is_a?(String)
      # IC ADDING:
      return if filename.empty?
      # END

      output.puts "From: #{Crystal.relative_filename(filename)}:#{line_number}:#{column_number} #{a_def_owner}#{hashtag}#{a_def.name}:"
    else
      output.puts "From: #{location} #{a_def_owner}#{hashtag}#{a_def.name}:"
    end

    output.puts

    source =
      case filename
      in String
        File.read(filename)
      in VirtualFile
        filename.source
      in Nil
        nil
      end

    return unless source

    if @context.program.color?
      begin
        # We highlight the entire file. We could try highlighting each
        # individual line but that won't work well for heredocs and other
        # constructs. Also, highlighting is pretty fast so it won't be noticeable.
        #
        # TODO: in reality if the heredoc starts way before the lines we show,
        # we lose the command that flips the color on. We should probably do
        # something better here, but for now this is good enough.
        # IC MODIFICATION:
        source = IC::Highlighter.highlight(source, toggle: @context.program.color?)
        # WAS:
        # source = Crystal::SyntaxHighlighter::Colorize.highlight(source)
        # END
      rescue
        # Ignore highlight errors
      end
    end

    lines = source.lines

    min_line_number = {location.line_number - 5, 1}.max
    max_line_number = {location.line_number + 5, lines.size}.min

    max_line_number_size = max_line_number.to_s.size

    min_line_number.upto(max_line_number) do |line_number|
      line = lines[line_number - 1]
      if line_number == location.line_number
        output.print " => "
      else
        output.print "    "
      end

      # IC ADDING:
      if (filename = location.filename).is_a? TopLevelExpressionVirtualFile
        line_number += filename.initial_line_number
      end
      # END

      # Pad line number if needed
      line_number_size = line_number.to_s.size
      (max_line_number_size - line_number_size).times do
        output.print ' '
      end

      output.print @context.program.colorize(line_number).blue
      output.print ": "
      output.puts line
    end
    output.puts
  end
end
