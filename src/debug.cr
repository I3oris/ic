module ICR
  # ## Override some methods to display useful debug infos : ###

  def self.display_result
    @@result.print_debug
    previous_def
  end

  private def self.run_last_expression(last_ast_node, ast_node)
    puts
    e = ast_node.expressions[-1]
    e.print_debug unless e.is_a? Crystal::FileNode
    puts

    previous_def
  end

  private def self.run_method_body(a_def)
    puts
    context = @@callstack.last
    puts "====== Call #{context.function_name} (#{context.receiver.try &.type.cr_type}) ======"
    puts a_def.body.print_debug

    ret = previous_def

    puts
    puts "===== End Call #{context.function_name} ======"

    ret
  end

  module Primitives
    def self.call(p : Crystal::Primitive)
      puts "Primitve called: #{p.name}:#{p.type}:#{p.extra}"
      previous_def
    end
  end

  class ICRObject
    def print_debug
      print "\n=== ICRObject: 0x#{@raw.address.to_s(16)}"
      if @type.reference_like?
        addr = @raw.as(UInt64*).value
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

  class ICRType
    def print_debug(visited = [] of ICRType, indent = 0)
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

class Crystal::ASTNode
  def print_debug(visited = [] of Crystal::ASTNode, indent = 0)
    if self.in? visited
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
