class Crystal::GenericInstanceType
  def generics
    generics = {} of String => ICR::ICRType
    @type_vars.each do |name,ast|
      generics[name] = ICR::ICRType.new ast.as(Crystal::Var).type
    end
    generics
  rescue
    bug "Cannot get generics vars for #{self}"
  end
end

module ICR
  alias Byte = UInt8


  class ICRType # TODO make all methods class methods
    getter size : UInt64
    getter cr_type : Crystal::Type
    # nil_type?
    # instance_vars
    # all_instance_vars

    getter generics = {} of String => ICRType
    @instance_vars = {} of String => {UInt64, ICRType}
    getter class_size = 0u64

    def struct?
      @cr_type.struct?
    end

    private def self.llvm_struct_type?(cr_type)
      (cr_type.is_a?(Crystal::NonGenericClassType) || cr_type.is_a?(Crystal::GenericClassInstanceType)) &&
        !cr_type.is_a?(Crystal::PointerInstanceType) && !cr_type.is_a?(Crystal::ProcInstanceType)
    end

    # don't use that for classes
    def self.instance_size_of(cr_type : Crystal::Type)
      return 0u64 if cr_type.nil_type?
      return 1u64 if cr_type.bool_type?

      llvm_typer = ICR.program.llvm_typer
      if llvm_struct_type?(cr_type)
        llvm_typer.size_of(llvm_typer.llvm_struct_type(cr_type))
      else
        llvm_typer.size_of(llvm_typer.llvm_embedded_type(cr_type))
      end
    end

    def self.size_of(cr_type : Crystal::Type)
      if cr_type.struct? # if !class?
        memory_size_of(cr_type)
      else
        8
      end
    end

    def initialize(@cr_type : Crystal::Type)
      @instance_vars = {} of String => Tuple(UInt64, ICRType)
      @size = 0u64


      @size = ICRType.instance_size_of(@cr_type)

      if !struct?
        @class_size = @size
        @size = 8_u64
        {% if flag?(:_debug) %}
          puts "SIZE OF #{@cr_type} = #{@size}(#{@class_size})"
        {% end %}
      end

      if (cr_type=@cr_type).is_a? Crystal::GenericInstanceType
        # @generics = cr_type.generic_type.instantiated_types.map { |t| ICRType.new(t).as(ICRType) }
        @generics = cr_type.generics
      end

      begin
        i = 0u64
        @cr_type.all_instance_vars.each do |name,ivar|
          {% if flag?(:_debug) %}
            puts "  size of #{@cr_type}.#{name} = #{ICRType.size_of(ivar.type)}"
          {% end %}
          @instance_vars[name] = {i,ICRType.new(ivar.type)} #ivar.type
          i += ICRType.size_of(ivar.type)
        rescue e
          puts "  BUG with #{ivar}: #{e.message}"
        end
      rescue
        # we enter here when @cr_type doesn't implement instance_vars
        # TODO: found a proper way to know if a Crystal::Type implements instance_vars
      end
    end

    def type_of(name)
      @instance_vars[name][1]
    end

    # Used if recurive type are defined
    def set_type_of(name, type : ICRType)
      @instance_vars[name] = {@instance_vars[name][0], type}
    end

    def read_ivar(name, src, dst)
      i, type = @instance_vars[name]
      (src + i).copy_to(dst, type.size)
    end

    def write_ivar(name, src, dst)
      i, type = @instance_vars[name]
      (dst + i).copy_from(src, type.size)
    end

    def self.pointer_of(generic : Crystal::Type)
      ICRType.new(ICR.program.pointer_of(generic))
    end

    def self.bool
      ICRType.new(ICR.program.bool)
    end

    def self.int32
      ICRType.new(ICR.program.int32)
    end

    def self.uint64
      ICRType.new(ICR.program.uint64)
    end

    def self.nil
      ICRType.new(ICR.program.nil)
    end
  end

  class ICRObject
    getter type : ICRType
    getter raw : Pointer(Byte)
    getter dont_collect : Pointer(Byte)? = nil

    def initialize(@type)
      if @type.struct?
        @raw = Pointer(Byte).malloc(@type.size)
      else
        @raw = Pointer(Byte).malloc(8)
        ref = Pointer(Byte).malloc(@type.class_size)
        @dont_collect = ref
        @raw.as(UInt64*).value = ref.address
      end
    end

    def [](name)
      obj = ICRObject.new(@type.type_of(name))
      if @type.struct?
        @type.read_ivar(name, @raw, obj.raw)
      else
        addr = @raw.as(UInt64*).value
        ref = Pointer(Byte).new(addr)
        @type.read_ivar(name, ref, obj.raw)
      end
      obj
    end

    def []=(name, value : ICRObject)
      if @type.struct?
        @type.write_ivar(name, value.raw, @raw)
      else
        addr = @raw.as(UInt64*).value
        ref = Pointer(Byte).new(addr)
        @type.write_ivar(name, value.raw, ref)
      end
      value
    end

    def truthy?
      !falsey?
    end

    def falsey?
      t = @type.cr_type
      t.nil_type? || (t.bool_type? && self.as_bool == false) #|| is_null_pointer?
    end

    def result
      case t = @type.cr_type.to_s
      when "Int32" then self.as_int32.to_s
      when "UInt64" then self.as_uint64.to_s
      when "Bool" then self.as_bool.to_s
      when "Nil" then "nil"
      else
        "#<#{t}:#{self.object_id}>"
      end
    end

    {% for t in %w(Int32 UInt64 Bool) %}
      def as_{{t.downcase.id}}
        @raw.as({{t.id}}*).value
      end

      def as_{{t.downcase.id}}=(value : {{t.id}})
        @raw.as({{t.id}}*).value = value
      end
    {% end %}

    def as_number(type : T.class) forall T
      @raw.as(T*).value
    end

    def set_as_number(type : T.class, value) forall T
      @raw.as(T*).value = value
    end

  end

  def self.bool(value : Bool)
    obj = ICRObject.new(ICRType.bool)
    obj.as_bool = value
    obj
  end

  def self.int32(value)
    obj = ICRObject.new(ICRType.int32)
    obj.as_int32 = value
    obj
  end

  def self.uint64(value : UInt64)
    obj = ICRObject.new(ICRType.uint64)
    obj.as_uint64 = value
    obj
  end

  def self.number(value : Int32)
    obj = ICRObject.new(ICRType.new(ICR.program.int32))
    obj.as_int32 = value
    obj
  end

  def self.number(value : UInt64)
    obj = ICRObject.new(ICRType.new(ICR.program.uint64))
    obj.as_uint64 = value
    obj
  end

  def self.number(value)
    todo "#{value.class} to ICRObject"
  end

  def self.nil
    ICRObject.new(ICRType.nil)
  end
end