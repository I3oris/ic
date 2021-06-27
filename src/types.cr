alias Byte = Void

module IC
  alias Type = Crystal::Type
end

class Crystal::Type
  # The size that this `Type` takes, Int32: 4, Bool: 1, reference_like types: 8 (address), Nil: 0, ...
  getter ic_size : UInt64? { reference? ? 8u64 : self.llvm_size }

  # The size allocated for this type
  getter ic_class_size : UInt64? { self.llvm_size }

  # Map associating each instance var name with its offset and its Type.
  private getter ic_ivars_layout : Hash(String, {UInt64, Type})? { get_ivars_layout }

  # The size that this `Type` takes, while it is used on a assignment or a copy.
  # Same as `ic_size` apart for Nil that is considered as a reference and are sized to 8.
  # This happens on `foo.bar = nil`, where we want erase the reference to `bar` and size of Nil isn't zero.
  def copy_size
    nil_type? ? 8u64 : self.ic_size
  end

  private def get_ivars_layout
    ivars_layout = {} of String => {UInt64, Type}

    offset = 0u64
    each_ivar_types do |name, type|
      ivars_layout[name] = {offset, type}

      # Align addresses:
      # offset = 8u64 + (offset%8u64) if type.reference?

      offset += type.ic_size
    end

    ivars_layout
  end

  private def llvm_size
    return 0u64 if nil_type?
    return 1u64 if bool_type?

    llvm = IC.program.llvm_typer
    llvm_type = llvm_struct_type? ? llvm.llvm_struct_type(self) : llvm.llvm_embedded_type(self)

    llvm.size_of(llvm_type)
  end

  private def llvm_struct_type?
    (is_a?(NonGenericClassType) || is_a?(GenericClassInstanceType)) &&
      !is_a?(PointerInstanceType) && !is_a?(ProcInstanceType)
  end

  def map_ivars(& : String -> T) forall T
    a = [] of T
    self.ic_ivars_layout.each_key do |name|
      a << yield name
    end
    a
  end

  def offset_and_type_of(name)
    self.ic_ivars_layout[name]? || ic_error "Cannot found the ivar #{name}. Defining ivars on a type isn't retroactive yet."
  end

  def update_layout
    # layout = get_ivars_layout
    # if @ic_ivars_layout.size > layout.size
    #   unless reference?
    #     ic_error "Cannot add instance vars on struct types (#{self}), \
    #       this would enlarge the type and break arrays or references of this type"
    #   end
    #   @ic_ivars_layout = layout
    # end
    @ic_ivars_layout = get_ivars_layout
  end

  def <(other : Type)
    self_type = self.devirtualize
    other_type = other.devirtualize
    !!(self_type != other_type && self_type.implements?(other_type))
  end

  def <=(other : Type)
    self_type = self.devirtualize
    other_type = other.devirtualize
    !!self_type.implements?(other_type)
  end

  def string?
    self.is_a? NamedType && self.name == "String"
  end

  def array?
    self.is_a? NamedType && self.name == "Array"
  end

  def union?
    self.is_a? UnionType
  end

  def instantiatable?
    !self.union? && !self.is_a? VirtualType
  end

  def reference?
    nil_type? ? false : reference_like?
  end

  def pointer_type_var
    raise "Called pointer_type_var on a non-pointer type"
  end

  def pointer_element_size
    pointer_type_var.ic_size
  end
end

class Crystal::PointerInstanceType
  def pointer_type_var
    @type_vars["T"].type
  end
end

class Crystal::Type
  # Yields each ivar with its type: {name, Type}
  def each_ivar_types(&)
    # classes start with a TYPE_ID : Int32
    if self.reference?
      yield "TYPE_ID", IC.program.int32
    end

    return unless is_a? InstanceVarContainer

    self.all_instance_vars.each do |name, ivar|
      yield name, ivar.type
    end
  end
end

class Crystal::UnionType
  # Add a virtual ivar "TYPE_ID", on the first slot of an union
  def each_ivar_types(&)
    yield "TYPE_ID", IC.program.int32
  end
end

class Crystal::TupleInstanceType
  # Add virtual ivars ("0","1","2",..) for each field
  def each_ivar_types(&)
    self.tuple_types.each_with_index do |type, i|
      yield i.to_s, type
    end
  end
end

class Crystal::NamedTupleInstanceType
  # Add virtual ivars ("0","1","2",..) for each field
  def each_ivar_types(&)
    self.entries.each_with_index do |named_arg, i|
      yield i.to_s, named_arg.type
    end
  end
end
