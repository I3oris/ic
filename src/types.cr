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

      @size, @class_size = ICRType.size_of(@cr_type)

      if (cr_type = @cr_type).responds_to? :generics
        @generics = cr_type.generics
      end

      # Check instances vars of this type, and store the offset and the type for each ivar
      # Tuple and NamedTuple are seen like if they have ivar "0","1","2",... so the type and the offset
      # for each field are stored here.
      if @cr_type.allows_instance_vars? # is_a? InstanceVarContainer, responds_to? :each_ivar_types
        offset = 0u64
        # classes start with a TYPE_ID : Int32
        if !struct? # self.reference_like? ??
          t = ICRType.int32
          @instance_vars["TYPE_ID"] = {offset, t}
          offset += t.size
        end

        @cr_type.each_ivar_types do |name, type|
          t = ICRType.new(type)

          @instance_vars[name] = {offset, t} # type doesn't matter actually, only size matter, type become correct only after the ivar is sets
          offset += t.size
        rescue e
          bug "Cannot get the size of #{@cr_type}.#{name}: #{e.message}"
        end
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
      end
    end

    def type_of(name)
      @instance_vars[name]?.try &.[1] || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."
    end

    def offset_and_type_of(name)
      @instance_vars[name]? || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."
    end

    # To use if recursive type are defined
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

    # Return the size and the instance size of a Crystal::Type
    # For classes, size is 8 and instance size is the size of the data of the classes
    def self.size_of(cr_type : Crystal::Type)
      return 0u64, 0u64 if cr_type.nil_type?
      return 1u64, 0u64 if cr_type.bool_type?

      llvm = ICR.program.llvm_typer
      size = if llvm_struct_type?(cr_type)
               llvm.size_of(llvm.llvm_struct_type(cr_type))
             else
               llvm.size_of(llvm.llvm_embedded_type(cr_type))
             end

      cr_type.struct? ? {size, 0u64} : {8u64, size}
    end

    private def self.llvm_struct_type?(cr_type)
      (cr_type.is_a?(Crystal::NonGenericClassType) || cr_type.is_a?(Crystal::GenericClassInstanceType)) &&
        !cr_type.is_a?(Crystal::PointerInstanceType) && !cr_type.is_a?(Crystal::ProcInstanceType)
    end

    # Creates the corresponding ICRTypes:

    def self.pointer_of(generic : Crystal::Type)
      ICRType.new(ICR.program.pointer_of(generic))
    end

    {% for t in %w(Bool Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64 Float32 Float64 Nil Char String) %}
      def self.{{t.downcase.id}}
        ICRType.new(ICR.program.{{t.downcase.id}})
      end
    {% end %}
  end
end

class Crystal::Type
  def <(other : Crystal::Type)
    self_type = self.devirtualize
    other_type = other.devirtualize
    !!(self_type != other_type && self_type.implements?(other_type))
  end

  def <=(other : Crystal::Type)
    self_type = self.devirtualize
    other_type = other.devirtualize
    !!self_type.implements?(other_type)
  end

  def each_ivar_types(&)
    self.all_instance_vars.each do |name, ivar|
      yield name, ivar.type
    end
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
  rescue e
    bug "Cannot get generics vars for #{self}, cause: #{e}"
  end
end

class Crystal::MetaclassType
  def each_ivar_types(&)
    yield "type_id", ICR.program.int32
  end
end

class Crystal::GenericClassInstanceMetaclassType
  def each_ivar_types(&)
    yield "type_id", ICR.program.int32
  end
end

class Crystal::GenericModuleInstanceMetaclassType
  def each_ivar_types(&)
    yield "type_id", ICR.program.int32
  end
end

class Crystal::UnionType
  def each_ivar_types(&)
    yield "type_id", ICR.program.int32
  end
end

class Crystal::TupleInstanceType
  def generics
    {} of String => ICR::ICRType
  end

  def each_ivar_types(&)
    self.tuple_types.each_with_index do |type, i|
      yield i.to_s, type
    end
  end
end

class Crystal::NamedTupleInstanceType
  def generics
    {} of String => ICR::ICRType
  end

  def each_ivar_types(&)
    self.entries.each_with_index do |named_arg, i|
      yield i.to_s, named_arg.type
    end
  end
end
