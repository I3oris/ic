def debug_msg(msg)
  IC.debug_indent
  puts msg
end

module IC
  # ## Override some methods to display useful debug infos : ###

  def self.display_result
    @@result.print_debug
    previous_def
  end

  def self.parse(text)
    ast = previous_def
    puts
    ast.print_debug
    puts
    ast
  end

  module CallStack
    class_getter callstack
  end

  module VarStack
    class_getter vars
  end

  def self.debug_indent
    CallStack.callstack.size.times { print "  " }
  end

  def self.print_callstack
    print "["
    print CallStack.callstack.join("/") { |c| c.name }
    print "]"
  end

  def self.print_vars
    VarStack.vars.last.vars.each do |name, value|
      debug_msg "#{name} : #{value.type.cr_type} = #{value.result}"
    end
  end

  # class_getter yieldstack

  private def self.run_method_body(a_def)
    # context = CallStack.callstack.last.as(CallStack::FunctionCallContext)
    context = CallStack.last?.not_nil!

    puts
    IC.debug_indent
    print "\b\b===== Call #{context.name} "
    print_callstack
    puts " ====="

    if r = context.receiver
      debug_msg "[receiver] : #{r.type.cr_type} = #{r.result}"
    end
    print_vars

    ret = previous_def

    debug_msg "\b\b===== End Call #{context.name}, returns #{ret.result} ====="
    ret
  end

  def self.yield(args) : ICObject
    puts
    IC.debug_indent
    print "=== Yield #{args.join(", ") { |a| a.result }} "
    print_callstack
    puts " ==="
    print_vars
    puts

    ret = previous_def

    debug_msg "=== End yield, returns #{ret.result} ==="
    ret
  end

  def self.handle_break(e, id)
    if e.call_id == id
      debug_msg "-> #{id} rescue Break"
      e.value
    else
      debug_msg "-> #{id} forward Break"
      ::raise e
    end
  end

  def self.handle_next(e, id)
    debug_msg "-> #{id} rescue Next"
    previous_def
  end

  def self.handle_return(e)
    debug_msg "-> rescue Return"
    previous_def
  end

  module Primitives
    def self.call(p : Crystal::Primitive)
      debug_msg "Primitve called: #{p.name}:#{p.type}:#{p.extra}"
      previous_def
    end
  end

  class ICObject
    def print_debug
      return if nop?
      print "\n=== ICObject: 0x#{@raw.address.to_s(16)}"
      if @type.reference_like?
        addr = @raw.as(UInt64*).value
        if addr == 0
          puts
          @type.print_debug
          return
        end
        ref = Pointer(Byte).new(addr)
        print " -> 0x#{ref.address.to_s(16)}"
      end
      puts
      @type.print_debug
      puts "==="
      if @type.cr_type.pointer?
        # for pointers display the first allocated slot
        size = @type.type_vars["T"].size
        addr = @raw.as(UInt64*).value
        data = Pointer(Byte).new(addr)
      else
        size = @type.reference_like? ? @type.class_size : @type.size
        data = self.data
      end
      size.times do |i|
        print '_' if i % 2 == 0
        print sprintf("%02x", data.as(UInt8*).[i])
        if (i + 1) % 4 == 0
          print "("
          print (data + (i + 1 - 4)).as(Int32*).value
          print ")\n"
        end
      end
      puts
      puts "==="
    end
  end

  class ICType
    def print_debug(visited = [] of ICType, indent = 0)
      if self.in? visited
        print "..."
        return
      end
      visited << self

      print "#{@cr_type}[#{@size}]"
      print "(#{@class_size})" if @cr_type.reference_like?
      print ':' unless @instance_vars.empty?
      puts
      @instance_vars.each do |name, layout|
        print "  "*(indent + 1)
        print "#{name}[+#{layout[0]}]: \t"
        layout[1].print_debug(visited, indent + 1)
      end
    end
  end
end

class Crystal::Next
  def run
    debug_msg "<- throws Next"
    previous_def
  end
end

class Crystal::Break
  def run
    debug_msg "<- throws Break #{self.target.object_id}"
    previous_def
  end
end

class Crystal::Return
  def run
    debug_msg "<- throws Return"
    previous_def
  end
end

class Crystal::ASTNode
  def print_debug(visited = [] of Crystal::ASTNode, indent = 0)
    if (self.in? visited) || self.is_a? Crystal::FileNode
      print "..."
      return
    end
    visited << self

    print {{@type}}
    puts ':'
    {% for ivar in @type.instance_vars.reject { |iv| %w(location end_location name_location doc observers parent_visitor dirty dependencies visibility).includes? iv.stringify } %}
      print "  "*(indent+1)
      print "@{{ivar}} = "
      if (ivar = @{{ivar}}).is_a? Crystal::ASTNode
        ivar.print_debug(visited,indent+1)
      else
        print @{{ivar}}.inspect
      end
      puts
    {% end %}
  end
end
