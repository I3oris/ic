module ICR
  alias Byte = UInt8

  # ICRType is a wrapper for Crystal::Type adding some informations about the
  # binary layout, and the type size.
  class ICRType
    getter cr_type : Crystal::Type
    getter generics = {} of String => ICRType
    getter size = 0u64
    getter class_size = 0u64

    # Map associating ivar name with its offset and its ICRType.
    @instance_vars = {} of String => {UInt64, ICRType}

    def struct?
      @cr_type.struct?
    end

    def initialize(@cr_type : Crystal::Type)
      @instance_vars = {} of String => Tuple(UInt64, ICRType)

      @size = 0u64
      @size = ICRType.instance_size_of(@cr_type)

      if !struct?
        @class_size = @size
        @size = 8_u64
      end

      if (cr_type = @cr_type).is_a? Crystal::GenericInstanceType
        @generics = cr_type.generics
      end

      begin
        offset = 0u64
        @cr_type.all_instance_vars.each do |name, ivar|
          @instance_vars[name] = {offset, ICRType.new(ivar.type)}
          offset += ICRType.size_of(ivar.type)
        rescue e
          bug "Cannot get the size of #{@cr_type}.#{ivar}: #{e.message}"
        end
      rescue
        # we enter here when @cr_type doesn't implement instance_vars
        # TODO: found a proper way to know if a Crystal::Type implements instance_vars
      end

      {% if flag?(:_debug) %}
        self.print_debug
      {% end %}
    end

    def print_debug(visited = [] of ICRType, indent = 0)
      if self.in? visited
        print "..."
        return
      end
      visited << self

      print "ICRType #{@cr_type}[#{@size}]"
      print "(#{@class_size})" unless struct?
      print ':' unless @instance_vars.empty?
      puts
      @instance_vars.each do |name, layout|
        print "  "*(indent + 1)
        print "#{name}[#{layout[0]}]: "
        layout[1].print_debug(visited, indent + 1)
        # puts
      end
    end

    def type_of(name)
      @instance_vars[name]?.try &.[1] || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."
    end

    # Used if recursive type are defined
    def set_type_of(name, type : ICRType)
      @instance_vars[name] = {@instance_vars[name][0], type}
    end

    # Considers *src* as the raw binary of this ICRType
    # then coping binary data of a *src* ivar to *dst*, considering
    # that *dst* is a raw binary of the ICRType of ivar.
    #
    # Example:
    # ```
    # struct Foo
    #   @x : Int32
    #   @y : Int32
    # end
    #
    # foo = Foo.new
    #
    # var = foo.@y
    # ```
    # Supposing this type represent Foo
    #
    # `read_ivar("y",foo_src, var_dst)` will copy
    # the bytes 4 to 8 from foo_src, to var_dst
    def read_ivar(name, src, dst)
      i, type = @instance_vars[name]? || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."
      (src + i).copy_to(dst, type.size)
    end

    # Same idea of read_ivar, but *dst* is considered as this ICRType.
    def write_ivar(name, src, dst)
      i, type = @instance_vars[name]? || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."
      (dst + i).copy_from(src, type.size)
    end

    # def generic!(name)
    #   @cr_type.as(Crystal::GenericInstanceType).type_vars[name].as(Crystal::Var).type
    # rescue
    #   bug "Cannot get generics vars for #{self}"
    # end

    def self.instance_size_of(cr_type : Crystal::Type)
      return 0u64 if cr_type.nil_type?
      return 1u64 if cr_type.bool_type?

      llvm = ICR.program.llvm_typer
      if llvm_struct_type?(cr_type)
        llvm.size_of(llvm.llvm_struct_type(cr_type))
      else
        llvm.size_of(llvm.llvm_embedded_type(cr_type))
      end
    end

    # Give the size of binary to allocate for an ICRObject, 8 for classes because
    # there are pointer.
    def self.size_of(cr_type : Crystal::Type)
      if cr_type.struct? # if !class?
        instance_size_of(cr_type)
      else
        8
      end
    end

    private def self.llvm_struct_type?(cr_type)
      (cr_type.is_a?(Crystal::NonGenericClassType) || cr_type.is_a?(Crystal::GenericClassInstanceType)) &&
        !cr_type.is_a?(Crystal::PointerInstanceType) && !cr_type.is_a?(Crystal::ProcInstanceType)
    end

    # Creates the corresponding ICRTypes:

    def self.pointer_of(generic : Crystal::Type)
      ICRType.new(ICR.program.pointer_of(generic))
    end

    {% for t in %w(Bool Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Nil) %}
      def self.{{t.downcase.id}}
        ICRType.new(ICR.program.{{t.downcase.id}})
      end
    {% end %}
  end
end

class Crystal::GenericInstanceType
  # Give the generics (type_vars) as String => ICRType instead of String => ASTNode
  def generics
    generics = {} of String => ICR::ICRType
    @type_vars.each do |name, ast|
      generics[name] = ICR::ICRType.new ast.as(Crystal::Var).type
    end
    generics
  rescue
    bug "Cannot get generics vars for #{self}"
  end
end
