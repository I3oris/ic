module ICR
  alias Byte = Void

  # ICRType is a wrapper for Crystal::Type adding some informations about the
  # binary layout, and the type size.
  class ICRType
    getter cr_type : Crystal::Type
    getter type_vars = {} of String => ICRType
    getter size = 0u64
    getter class_size = 0u64

    # Map associating ivar name with its offset and its ICRType.
    @instance_vars = {} of String => {UInt64, ICRType}

    def initialize(@cr_type : Crystal::Type)
      @instance_vars = {} of String => Tuple(UInt64, ICRType)

      @size, @class_size = ICRType.size_of(@cr_type)

      if (cr_type = @cr_type).responds_to? :icr_type_vars
        @type_vars = cr_type.icr_type_vars
      end

      # Check instances vars of this type, and store the offset and the type for each ivar
      # Tuple and NamedTuple are seen like if they have ivar "0","1","2",... so the type and the offset
      # for each field are stored here.
      if @cr_type.allows_instance_vars?
        offset = 0u64
        @cr_type.each_ivar_types do |name, type|
          t = ICRType.new(type)

          @instance_vars[name] = {offset, t}
          offset += t.size
        rescue e
          bug! "Cannot get the size of #{@cr_type}.#{name}: #{e.message}"
        end
      end
    end

    def reference_like?
      @cr_type.reference_like?
    end

    def instantiable?
      !@cr_type.is_a? Crystal::UnionType && !@cr_type.is_a? Crystal::VirtualType
    end

    def offset_and_type_of(name)
      @instance_vars[name]? || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."
    end

    # To use if recursive type are defined
    def set_type_of(name, type : ICRType)
      @instance_vars[name] = {@instance_vars[name][0], type}
    end

    def copy_size
      @cr_type.nil_type? ? 8u64 : @size
    end

    # Considers *src* as this *type*, and returns the ICRObject read.
    # Always return the instance type, never a Union or VirtualType.
    # If *type* is Nil, return ICR.nil without read the data.
    #
    # Expect that the data is:
    #
    # src -> ref -> | TYPE_ID (4)
    #               | data...
    #
    # for reading a reference-like type (Classes, Union of Classes,...).
    #
    # src -> null (for nil reference-like).
    #
    # src -> |0| TYPE_ID (4)
    #        |8| data|ref...
    #
    # for reading an union type (unbox).
    def read(from src : Byte*)
      case @cr_type
      when .nil_type?
        return ICR.nil
      when .reference_like?
        p = src.as(Int32**)
        return ICR.nil if p.value.null?

        id = p.value.value
      when Crystal::UnionType
        id = src.as(Int32*).value
        src += 8
      end

      # Gets the instance type if a TYPE_ID have been read (UnionType and reference_like):
      instance_type = id ? ICRType.new(ICR.type_from_id(id)) : self # devirtualize?

      obj = ICRObject.new(instance_type)
      obj.raw.copy_from(src, instance_type.copy_size)
      obj
    end

    # Considers *dst* as this *type*, and write *value* to *dst*.
    # If *type* is Nil, return ICR.nil without writing the data.
    #
    #
    # writes with the format:
    #
    # dst -> ref -> | TYPE_ID (4)
    #               | data...
    #
    # for reference-like type.
    #
    # dst -> null (for nil reference-like).
    #
    #
    #
    # src -> |0| TYPE_ID (4)
    #        |8| data|ref...
    #
    # for union type (box).
    def write(value : ICRObject, to dst : Byte*)
      case @cr_type
      when .nil_type?
        return value
      when .reference_like?
        # including VirtualType,
        # reference_like UnionType,
        # and instance type Nil
      when Crystal::UnionType
        # box: write the TYPE_ID first:
        dst.as(Int32*).value = ICR.type_id(value.type.cr_type)
        dst += 8
      end

      value.raw.copy_to(dst, value.type.copy_size)
      value
    end

    # Considers *src* as this *type*, and return the value of the ivar *name*
    def read_ivar(name, from src : Byte*)
      index, type = @instance_vars[name]? || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."

      type.read from: (src + index)
    end

    # Considers *dst* as this *type*, and set *value* to the ivar *name*
    def write_ivar(name, value : ICRObject, to dst : Byte*)
      index, type = @instance_vars[name]? || icr_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."

      type.write value, to: (dst + index)
    end

    def map_ivars(& : String -> T) forall T
      a = [] of T
      @instance_vars.each_key do |name|
        a << yield name
      end
      a
    end

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

      cr_type.reference_like? ? {8u64, size} : {size, 0u64}
    end

    private def self.llvm_struct_type?(cr_type)
      (cr_type.is_a?(Crystal::NonGenericClassType) || cr_type.is_a?(Crystal::GenericClassInstanceType)) &&
        !cr_type.is_a?(Crystal::PointerInstanceType) && !cr_type.is_a?(Crystal::ProcInstanceType)
    end

    # Creates the corresponding ICRTypes:

    def self.pointer_of(type_var : Crystal::Type)
      ICRType.new(ICR.program.pointer_of(type_var))
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

  def string?
    self.to_s == "String"
  end

  def array?
    self.to_s.starts_with? "Array"
  end

  # Yields each ivar with its type: {name, ICRType}
  def each_ivar_types(&)
    todo "ivars on #{self} (#{self.class})" unless self.is_a? Crystal::InstanceVarContainer

    # classes start with a TYPE_ID : Int32
    if self.reference_like?
      yield "TYPE_ID", ICR.program.int32
    end

    self.all_instance_vars.each do |name, ivar|
      yield name, ivar.type
    end
  end
end

class Crystal::GenericInstanceType
  # Give the type_vars as String => ICRType instead of String => ASTNode
  def icr_type_vars
    type_vars = {} of String => ICR::ICRType
    @type_vars.each do |name, ast|
      type_vars[name] = ICR::ICRType.new ast.as(Crystal::Var).type
    end
    type_vars
  rescue e
    bug! "Cannot get type_vars for #{self}, cause: #{e}"
  end
end

class Crystal::UnionType
  # Add a virtual ivar "TYPE_ID", on the first slot of an union
  def each_ivar_types(&)
    yield "TYPE_ID", ICR.program.int32
  end
end

class Crystal::TupleInstanceType
  def icr_type_vars
    {} of String => ICR::ICRType
  end

  # Add virtual ivars ("0","1","2",..) for each field
  def each_ivar_types(&)
    self.tuple_types.each_with_index do |type, i|
      yield i.to_s, type
    end
  end
end

class Crystal::NamedTupleInstanceType
  def icr_type_vars
    {} of String => ICR::ICRType
  end

  # Add virtual ivars ("0","1","2",..) for each field
  def each_ivar_types(&)
    self.entries.each_with_index do |named_arg, i|
      yield i.to_s, named_arg.type
    end
  end
end

{% for metaclass in %w(MetaclassType GenericClassInstanceMetaclassType GenericModuleInstanceMetaclassType VirtualMetaclassType) %}
  class Crystal::{{metaclass.id}}
    def each_ivar_types(&)
    end
  end
{% end %}
