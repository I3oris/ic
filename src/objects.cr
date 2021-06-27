module IC
  # ICObject are transmitted through the AST Tree, and represents Object created with IC
  #
  # There are constituted of a `Type` and a pointer to the object (@address)
  # i.e for a Int32, raw will be a pointer on 4 bytes.
  #
  # For classes, raw will be a pointer on 8 bytes (ref), pointing itself on class data.
  #
  # The `Type` will give information of how to treat the binary object.
  struct ICObject
    # The address of this object, (representing an address on the stack):
    getter address : Pointer(Byte)

    # The **compile time** type of this object:
    getter type : Type

    getter? nop = false

    # Creates a new Object for literals, CONST, temporary Objects, and boxed/unboxed Object
    #
    # The returned object has is own address
    def self.create(type)
      new(type)
    end

    # Creates a new Object for vars, @@cvars, and $globals
    #
    # The returned object has is own address, but its type can be enlarged
    # with `with_merged_type` (if possible)
    def self.create_var(type : Type, value : ICObject) : ICObject
      var = new(type, resizable?: true)
      # var.allocate
      var.assign(value) unless value.nop?
      var
    end

    # Returns an object on an address, used for @ivars, or pointer_get.
    def self.sub(type, from address)
      new(type, address)
    end

    # Fictitious nop object, used on nodes that can't return, like a `Def` or a `ClassDef`.
    def self.nop
      new
    end

    # create:
    private def initialize(@type : Type, resizable? = false)
      if resizable?
        # Allocate min 8 bytes so we can store an address in this slot after
        # so if `x : Int32`, is re-assigned and change its type (`x = Foo.new`) we
        # can store the new value and keep the address of `x` (so eventual pointer or closure on x wont break)
        #
        # However changing `x` type by a bigger struct isn't supported yet, because this mean break eventual pointers and closures.
        #
        # NOTE: in no-prompt mode, inside a function or a `Assign`; the problem doesn't appear because the type of the var is always fully known
        # in advance.
        @address = Pointer(Byte).malloc({@type.ic_size, 16}.max)
      else
        @address = Pointer(Byte).malloc(@type.ic_size)
      end
    end

    # sub:
    private def initialize(@type : Type, @address : Byte*)
    end

    # nop:
    private def initialize
      @type = IC.program.nil
      @address = Pointer(Byte).null
      @nop = true
    end

    # If this object is a reference: allocate its reference:
    #
    # address -> ref -> | TYPE_ID (4)
    #                   | @ivar 1
    #                   | @ivar 2
    #                   | ...
    def allocate
      if @type.reference?
        @address = Pointer(Byte).malloc(8)
        @address.as(Byte**).value = Pointer(Byte).malloc(@type.ic_class_size)
        @address.as(Int32**).value.value = IC.type_id(@type)
      end
      self
    end

    # Unsafe cast without changing the object address.
    def hard_cast!(new_type)
      ICObject.sub(new_type, from: @address)
    end

    # Returns this object with an updated type
    #
    # Used to change the type of a local var but keeping its address e.g:
    # ```
    # x = 42
    # p = pointerof(x)
    # p.value # => 42
    #
    # x = "foo!"
    # # here x is updated to Int32|String and is boxed,
    # # then p is updated to Pointer(Int32|String)
    #
    # p.value # => "foo!" # works because x keep the same address.
    # ```
    #
    # The type cannot be update to a too lard type, because this need a reallocation
    # and we doesn't want change the object address.
    def updated(new_type)
      if {new_type.ic_size, 16}.max > {@type.ic_size, 16}.max
        # /!\ this will break pointers on this object!
        ic_error "Cannot enlarge the type #{@type} to #{new_type}"
        #
      end
      # TODO: execute missing @ivars initializers here!

      if new_type != @type
        obj = self.hard_cast!(new_type)
        obj.assign self
        obj
      else
        self
      end
    end

    # Returns:
    #   address -> data        (for value types)
    #   address -> ref -> data (for references)
    def data : Byte*
      if type.reference?
        @address.as(Byte**).value
      else
        @address
      end
    end

    # Read the ivar @name of this object, if possible
    def [](name) : ICObject
      offset, type = @type.offset_and_type_of(name)

      ICObject.sub(type, from: self.data + offset)
    end

    # Assign the ivar @name = *value*, if possible
    def []=(name, value : ICObject) : ICObject
      self[name].assign(value)
    end

    # ASSIGN: copy *value* into *self*
    #
    # * if self Nil: nothing to do (e.g assignment of ivar `@foo : Nil`)
    #
    # * if same type: simple copy byte to byte
    #
    # * value is unboxed (e.g `x : Int32 = 42||"42"`, `42||"42"` => `42`)
    #
    # * then is self is Union, we box it: (e.g `y : Int32|String = 42`)
    def assign(value : ICObject) : ICObject
      return value if @type.nil_type?

      if @type == value.type
        value.address.copy_to(@address, value.type.copy_size)
      else
        value = value.unboxed

        bug! "Cannot assign #{@type} <- #{value.type}" if value.type.ic_size > @type.ic_size

        if @type.union?
          self.box(value)
        else
          value.address.copy_to(@address, value.type.copy_size)
        end
      end
      value
    end

    # Box: Assign a *value* to this union type
    #
    # Format of union is:
    # | TYPE_ID    (4)
    # | padding    (4)
    # | data_union (...)
    #
    #
    # If the union is reference_like (e.g `String|Nil|AClass`)
    # format is:
    # | reference (8)
    #
    def box(value : ICObject)
      bug! "Cannot box to a non-union type (#{@type})" unless @type.union?

      value = value.unboxed
      # puts "box #{@type} <- #{value.type} (#{value.type.copy_size} bytes)"

      if @type.reference_like?
        # Write reference:
        @address.copy_from(value.address, value.type.copy_size)
        return self
      end

      # Write TYPE_ID and data_union:
      self.as_int32 = IC.type_id(value.type)
      (self.address + 8).copy_from(value.address, value.type.copy_size)
      self
    end

    # Returns a new object that box *self* with *new_type*:
    def boxed(new_type : Type) : ICObject
      case new_type
      when @type   then self
      when .union? then ICObject.create(new_type).box(self)
        # .virtual?
      else self
      end
    end

    # Returns a new object unboxed from *self*
    #
    # The object returned is always instantiatable and keep its address unless is was unboxed from an union
    def unboxed : ICObject
      if @type.virtual? || @type.union? && @type.reference_like?
        run_type = self.runtime_type
        self.hard_cast!(run_type)
      elsif @type.union?
        run_type = self.runtime_type

        obj = ICObject.create(run_type)
        obj.address.copy_from(@address + 8, run_type.copy_size)
        obj
      else
        self
      end
    end

    # Returns the runtime type of this object,
    # runtime type **Cannot** be union or virtual
    def runtime_type
      run_type =
        if @type.union? || @type.reference_like?
          IC.type_from_id(self.runtime_type_id)
        else
          @type
        end
      if !run_type.instantiatable?
        bug! "Runtime type should be instantiatable: not #{run_type}"
      end
      run_type
    end

    # Returns the type if of the `runtime` type
    def runtime_type_id
      case @type
      when .nil_type?
        IC.type_id(IC.program.nil)
      when .reference_like?
        if (data = self.data).null?
          # address -> null
          IC.type_id(IC.program.nil)
        else
          # address -> data -> | TYPE_ID
          #                | ...
          data.as(Int32*).value
        end
      when .union?
        # address -> | TYPE_ID
        #        | ...
        self.as_int32
      else
        # Otherwise, runtime type id is the compile time type id
        IC.type_id(@type)
      end
    end

    # Performs a safe cast (`as`):
    # returns a new boxed/unboxed value if needed
    # returns nil if cast is invalid.
    def cast?(to : Type?) : ICObject?
      bug! "cast from #{to} failed" if to.nil?

      if self.is_a(to)
        if @type == to
          self
        else
          value = self.unboxed

          if to.union?
            value.boxed(to)
          else
            value.hard_cast!(to)
          end
        end
      elsif (@type.pointer? && to.pointer?) ||
            (@type.pointer? && to.reference_like?) ||
            (to.pointer? && @type.reference_like?)
        self.hard_cast!(to)
      else
        puts "INVALID CAST #{@type}(#{self.runtime_type}) vs #{to}"
        nil
      end
    end

    # `is_a?` compares runtime type to the given type.
    def is_a(type : Type?)
      bug! ".is_a?(#{type}) failed" if type.nil?

      self.runtime_type <= type
    end

    def truthy?
      !falsey?
    end

    # Falsey if is nil, false, or null Pointer
    def falsey?
      value = self.unboxed

      value.type.nil_type? || (value.type.bool_type? && value.as_bool == false) || (value.type.pointer? && value.as_uint64 == 0u64)
    end

    # Returns a new ICObject(Pointer) pointing on the address of this object.
    def pointerof_self : ICObject
      IC.pointer_of(@type, address: @address.address)
    end

    # Returns a new ICObject(Pointer) pointing on the offset of *ivar*
    def pointerof(*, ivar : String) : ICObject
      offset, type = @type.offset_and_type_of(ivar)
      IC.pointer_of(type, address: (self.data + offset).address)
    end

    # Performs the implicit conversion between int-types or symbol to enum.
    def implicit_convert(to new_type) : ICObject
      case new_type
      when @type
        self
      when Crystal::EnumType
        if @type.is_a? Crystal::SymbolType
          IC.enum_from_symbol(new_type, self)
        end
      when Crystal::FloatType, Crystal::IntegerType
        case new_type.kind
        when :i8   then IC.number(self.as_number.to_i8)
        when :u8   then IC.number(self.as_number.to_u8)
        when :i16  then IC.number(self.as_number.to_i16)
        when :u16  then IC.number(self.as_number.to_u16)
        when :i32  then IC.number(self.as_number.to_i32)
        when :u32  then IC.number(self.as_number.to_u32)
        when :i64  then IC.number(self.as_number.to_i64)
        when :u64  then IC.number(self.as_number.to_u64)
        when :f32  then IC.number(self.as_number.to_f32)
        when :f64  then IC.number(self.as_number.to_f64)
        when :i128 then todo "implicit_convert #{@type} -> #{new_type}"
        when :u128 then todo "implicit_convert #{@type} -> #{new_type}"
        end
      end || self
    end
  end
end
