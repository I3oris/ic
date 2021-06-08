module IC
  def self.run_fun_body(receiver, a_def, args, ret_type) : ICObject
    if receiver.nil?
      todo "Top level fun '#{a_def.real_name}'"
    else
      type = receiver.type
      bug! "Trying to call a fun def on a non-LibType" if !type.is_a? Crystal::LibType

      IC::FunPrimitives.run_fun type.name, a_def.name, args, ret_type
    end
  end

  module FunPrimitives
    private MAX_VA_ARG = 10

    # We cannot known if a fun def return void (`m.return_type` always Nop)
    # So we list them here, this should not varies across platforms.
    private RETURN_VOID_LIST = {
      "LibC"  => %w(dl_iterate_phdr),
      "LibGC" => %w(init free collect add_roots enable disable set_handle_fork get_heap_usage_safe set_max_heap_size
        get_prof_stats push_all_eager set_on_collection_event set_warn_proc),
      "LibIntrinsics" => %w(debugtrap memcpy memmove memset va_start va_end pause),
    }

    # This special llvm-method cannot compile because theirs boolean argument must be know at compile time.
    private SKIP = %w(memcpy memmove memset countleading8 countleading16 countleading32 countleading64 countleading128 counttrailing8 counttrailing16 counttrailing32 counttrailing64 counttrailing128)

    def self.run_fun(lib_name, fun_name, args, ret_type) : ICObject
      # print_each_fun LibC

      # Because lib fun must be compiled statically, we generate a code that
      # map each know {lib_name,fun_name} to the true lib fun call
      {% begin %}
        case lib_name
         # Generates the entries for following libs:
         {% for lib_name in %w(LibC LibGC LibIntrinsics) %}
            when {{lib_name}}
              run_fun_on({{lib_name.id}}, fun_name, args, ret_type)
          {% end %}
        else todo "fun def '#{lib_name}.#{fun_name}'"
        end
      {% end %}
    end

    private def self.run_fun_on(lib_class : T, fun_name, args, ret_type) : ICObject forall T
      {% begin %}
        case fun_name
        # We will take the info given by the fun method `m` for generate the call:
        {% for m, i in T.resolve.methods %}
          # puts m
          {%
            lib_name = T.stringify
            fun_name = m.name
            fun_declaration = m.stringify                   # the string fun declaration
            have_va_args = fun_declaration.includes?("...") # true if fun contains va-vars
            returns_void = fun_declaration.ends_with?(" : Void") ||
                           RETURN_VOID_LIST[lib_name].includes?(fun_name.stringify) # true if fun returns void

            # all regular type of argument (e.g ["Pointer(Char)"] for printf):
            arg_types = m.args.map do |arg|
              arg.stringify.split(" : ")[-1]
            end
          %}
          {% if fun_declaration.empty? %}
            # `fun_declaration` turn out to be empty if `m` is a getter/setter on a lib global var (e.g. $environ)
            # so skip them.
          {% elsif fun_declaration.includes?("->") || arg_types.any?(&.includes? "Proc(") || SKIP.includes?(fun_name.stringify) %}
            # skip funs with callback for now
          {% else %}
            when {{fun_name.stringify}}
              # Generate the call:
              fun_body {{lib_name}}, {{fun_name.stringify}}, {{have_va_args}}, {{returns_void}}, [{{*arg_types}}] of String
          {% end %}
        {% end %}
        when "memcpy" then memcpy(args, ret_type)
        when "memmove" then memmove(args, ret_type)
        when "memset" then memset(args, ret_type)
        else todo "fun def '{{lib_name.id}}.#{fun_name}'"
          end
      {% end %}
    end

    # Generates the code to call a lib fun:
    #
    # For 'memcmp', generates:
    # ```
    # ret =
    #   LibC.memcmp(args[0].as!(Pointer(Void)), args[1].as!(Pointer(Void)), args[2].as!(UInt64))
    #
    # ic_object_of(ret, ret_type)
    # ```
    #
    # If returns void, generates (say tzset):
    # ```
    # ret = nil
    # LibC.tzset
    # ic_object_of(ret, ret_type)
    # ```
    #
    # If contains va_args (say printf):
    # ```
    # va_args = init_va_args(args, 1)
    # ret = LibC.printf(args[0].as!(Pointer(UInt8)), va_args[0], va_args[1], va_args[2], va_args[3], va_args[4], va_args[5], va_args[6], va_args[7], va_args[8], va_args[9])
    #
    # ic_object_of(ret, ret_type)
    # ```
    # `init_va_args` will return a array of *MAX_VA_ARG* var-args initialized or not depending of va-args given on *args*
    macro fun_body(lib_name, fun_name, have_va_args, returns_void, arg_types)
      {% if have_va_args %}
        va_args = init_va_args(args, {{arg_types.size}})
      {% end %}

      {% if returns_void %}
        ret = nil
      {% else %}
        ret =
      {% end %}
      {{lib_name.id}}.{{fun_name.id}}({{*arg_types.map_with_index do |t, i|
                                          "args[#{i}].as!(#{t.id})".id
                                        end}} \
                              {% if have_va_args %} \
                                {% for i in 0...MAX_VA_ARG %} \
                                , va_args[{{i}}] \
                                {% end %}
                              {% end %})

      ic_object_of(ret, ret_type)
    end

    # Because IC cannot know how many va-args will be used, it will always initialize `MAX_VA_ARG` va-args
    # and fill only the really used va-args at run-time.
    #
    # *args* : all args given to the fun.
    # *regular_args_size* : the number of args in the fun def, excluding the va-args.
    # Returns the array of initialized or not va_args
    private def self.init_va_args(args, regular_args_size)
      va_args = uninitialized StaticArray(UInt64, MAX_VA_ARG)
      nb_va_arg = args.size - regular_args_size
      raise "Too much variadic arguments : #{nb_va_arg} (max supported: #{MAX_VA_ARG})" if nb_va_arg > MAX_VA_ARG

      nb_va_arg.times do |i|
        va_args[i] = args[regular_args_size + i].as_va_arg
      end
      va_args
    end

    # Creates a ICObject from *ret*
    private def self.ic_object_of(ret, ret_type) : ICObject
      return IC.nil if ret.nil?
      size = sizeof(typeof(ret))

      # We must copy in a new pointer because *ret* is a local var
      p = Pointer(Void).malloc size
      p.copy_from pointerof(ret).as(Void*), size
      ICObject.new ret_type, from: p
    end

    private def self.memcpy(args, ret_type) : ICObject
      src = args[0].as!(Pointer(Void))
      dst = args[1].as!(Pointer(Void))
      len = args[2].as!(UInt64)
      volatile = args[3].as!(Bool)
      # this way volatile arg is known at compile time:
      if volatile
        Intrinsics.memcpy(src, dst, len, true)
      else
        Intrinsics.memcpy(src, dst, len, false)
      end
      ic_object_of(nil, ret_type)
    end

    private def self.memmove(args, ret_type) : ICObject
      src = args[0].as!(Pointer(Void))
      dst = args[1].as!(Pointer(Void))
      len = args[2].as!(UInt64)
      volatile = args[3].as!(Bool)
      if volatile
        Intrinsics.memmove(src, dst, len, true)
      else
        Intrinsics.memmove(src, dst, len, false)
      end
      ic_object_of(nil, ret_type)
    end

    private def self.memset(args, ret_type) : ICObject
      src = args[0].as!(Pointer(Void))
      val = args[1].as!(UInt8)
      len = args[2].as!(UInt64)
      volatile = args[3].as!(Bool)
      if volatile
        Intrinsics.memset(src, val, len, true)
      else
        Intrinsics.memset(src, val, len, false)
      end
      ic_object_of(nil, ret_type)
    end
  end
end
