module IC
  module FunPrimitives
    {% for type in %w(
                     SSizeT SizeT Int Long Double UidT GidT PidT OffT DlInfo ClockidT Timespec TimeT Timeval Tm SigsetT DivT IconvT
                     ModeT Termios Stat DevT PthreadAttrT PthreadCondattrT PthreadCondT PthreadMutexT PthreadT PthreadMutexattrT
                     Sockaddr SocklenT Addrinfo DIR Dirent FlockOp RUsage
                   ) %}
      alias {{type.id}} = LibC::{{type.id}}
    {% end %}

    alias PVoid = Pointer(Void)
    alias PChar = Pointer(LibC::Char)
    alias PInt = Pointer(LibC::Int)

    ALL_FUN = {
      "LibC" => {
        # "malloc" => { {SizeT}, PVoid },
        # "free"   => { {PVoid}, Void },
        # "write"  => { {Int, PVoid, SizeT}, SSizeT },
        # "exit"   => { {Int}, NoReturn },
        # "getpid" => {[] of Path, PidT},
        # "printf" => { {PChar, "UInt64"}, Int },
        "dlclose"  => { {PVoid}, Int },
        "dlerror"  => {[] of Path, PChar},
        "dlopen"   => { {PChar, Int}, PVoid },
        "dlsym"    => { {PVoid, PChar}, PVoid },
        "dladdr"   => { {PVoid, Pointer(DlInfo)}, Int },
        "printf"   => { {PChar, "Long"}, Int },
        "dprintf"  => { {Int, PChar, "Long"}, Int },
        "rename"   => { {PChar, PChar}, Int },
        "snprintf" => { {PChar, SizeT, PChar, "Long"}, Int },
        "memchr"   => { {PVoid, Int, SizeT}, PVoid },
        "memcmp"   => { {PVoid, PVoid, SizeT}, Int },
        "strcmp"   => { {PChar, PChar}, Int },
        "strerror" => { {Int}, PChar },
        "strlen"   => { {PChar}, SizeT },
        # "dl_iterate_phdr" => { {DlPhdrCallback, PVoid}, Void },
        "clock_gettime"   => { {ClockidT, Pointer(Timespec)}, Int },
        "clock_settime"   => { {ClockidT, Pointer(Timespec)}, Int },
        "gmtime_r"        => { {Pointer(TimeT), Pointer(Tm)}, Pointer(Tm) },
        "localtime_r"     => { {Pointer(TimeT), Pointer(Tm)}, Pointer(Tm) },
        "mktime"          => { {Pointer(Tm)}, TimeT },
        "tzset"           => {[] of Path, Void},
        "timegm"          => { {Pointer(Tm)}, TimeT },
        "kill"            => { {PidT, Int}, Int },
        "pthread_sigmask" => { {Int, Pointer(SigsetT), Pointer(SigsetT)}, Int },
        # "signal" => { {Int, (Int -> Void)} , (Int -> Void) },
        "sigemptyset" => { {Pointer(SigsetT)}, Int },
        "sigfillset"  => { {Pointer(SigsetT)}, Int },
        "sigaddset"   => { {Pointer(SigsetT), Int}, Int },
        "sigdelset"   => { {Pointer(SigsetT), Int}, Int },
        "sigismember" => { {Pointer(SigsetT), Int}, Int },
        "waitpid"     => { {PidT, Pointer(Int), Int}, PidT },
        "atof"        => { {PChar}, Double },
        "div"         => { {Int, Int}, DivT },
        "exit"        => { {Int}, NoReturn },
        "free"        => { {PVoid}, Void },
        "getenv"      => { {PChar}, PChar },
        "malloc"      => { {SizeT}, PVoid },
        "mkstemp"     => { {PChar}, Int },
        "mkstemps"    => { {PChar, Int}, Int },
        "putenv"      => { {PChar}, Int },
        "realloc"     => { {PVoid, SizeT}, PVoid },
        "realpath"    => { {PChar, PChar}, PChar },
        "setenv"      => { {PChar, PChar, Int}, Int },
        "strtof"      => { {PChar, Pointer(PChar)}, Float },
        "strtod"      => { {PChar, Pointer(PChar)}, Double },
        "unsetenv"    => { {PChar}, Int },
        "iconv"       => { {IconvT, Pointer(PChar), Pointer(SizeT), Pointer(PChar), Pointer(SizeT)}, SizeT },
        "iconv_close" => { {IconvT}, Int },
        "iconv_open"  => { {PChar, PChar}, IconvT },
        "chroot"      => { {PChar}, Int },
        "access"      => { {PChar, Int}, Int },
        "chdir"       => { {PChar}, Int },
        "chown"       => { {PChar, UidT, GidT}, Int },
        "close"       => { {Int}, Int },
        "dup2"        => { {Int, Int}, Int },
        "_exit"       => { {Int}, NoReturn },
        "execvp"      => { {PChar, Pointer(PChar)}, Int },
        "fdatasync"   => { {Int}, Int },
        "fork"        => {[] of Path, PidT},
        "fsync"       => { {Int}, Int },
        "ftruncate"   => { {Int, OffT}, Int },
        "getcwd"      => { {PChar, SizeT}, PChar },
        "gethostname" => { {PChar, SizeT}, Int },
        "getpgid"     => { {PidT}, PidT },
        "getpid"      => {[] of Path, PidT},
        "getppid"     => {[] of Path, PidT},
        "isatty"      => { {Int}, Int },
        "ttyname_r"   => { {Int, PChar, SizeT}, Int },
        "lchown"      => { {PChar, UidT, GidT}, Int },
        "link"        => { {PChar, PChar}, Int },
        "lockf"       => { {Int, Int, OffT}, Int },
        "lseek"       => { {Int, OffT, Int}, OffT },
        "pipe"        => { {StaticArray(Int, 2)}, Int },
        "read"        => { {Int, PVoid, SizeT}, SSizeT },
        "pread"       => { {Int, PVoid, SizeT, OffT}, SSizeT },
        "rmdir"       => { {PChar}, Int },
        "symlink"     => { {PChar, PChar}, Int },
        "readlink"    => { {PChar, PChar, SizeT}, SSizeT },
        # "syscall" => { {Long, ...} , Long },
        "sysconf"   => { {Int}, Long },
        "unlink"    => { {PChar}, Int },
        "tcgetattr" => { {Int, Pointer(Termios)}, Int },
        "tcsetattr" => { {Int, Int, Pointer(Termios)}, Int },
        "cfmakeraw" => { {Pointer(Termios)}, Void },
        "chmod"     => { {PChar, ModeT}, Int },
        "fstat"     => { {Int, Pointer(Stat)}, Int },
        "lstat"     => { {PChar, Pointer(Stat)}, Int },
        "mkdir"     => { {PChar, ModeT}, Int },
        "mkfifo"    => { {PChar, ModeT}, Int },
        "mknod"     => { {PChar, ModeT, DevT}, Int },
        "stat"      => { {PChar, Pointer(Stat)}, Int },
        "umask"     => { {ModeT}, ModeT },
        # "fcntl" => { {Int, Int, ...} , Int },
        # "open" => { {PChar, Int, ...} , Int },
        "pthread_attr_destroy"      => { {Pointer(PthreadAttrT)}, Int },
        "pthread_attr_getstack"     => { {Pointer(PthreadAttrT), Pointer(PVoid), Pointer(SizeT)}, Int },
        "pthread_condattr_destroy"  => { {Pointer(PthreadCondattrT)}, Int },
        "pthread_condattr_init"     => { {Pointer(PthreadCondattrT)}, Int },
        "pthread_condattr_setclock" => { {Pointer(PthreadCondattrT), ClockidT}, Int },
        "pthread_cond_broadcast"    => { {Pointer(PthreadCondT)}, Int },
        "pthread_cond_destroy"      => { {Pointer(PthreadCondT)}, Int },
        "pthread_cond_init"         => { {Pointer(PthreadCondT), Pointer(PthreadCondattrT)}, Int },
        "pthread_cond_signal"       => { {Pointer(PthreadCondT)}, Int },
        "pthread_cond_timedwait"    => { {Pointer(PthreadCondT), Pointer(PthreadMutexT), Pointer(Timespec)}, Int },
        "pthread_cond_wait"         => { {Pointer(PthreadCondT), Pointer(PthreadMutexT)}, Int },
        # "pthread_create" => { {Pointer(PthreadT), Pointer(PthreadAttrT), (PVoid -> PVoid), PVoid} , Int },
        "pthread_detach"            => { {PthreadT}, Int },
        "pthread_getattr_np"        => { {PthreadT, Pointer(PthreadAttrT)}, Int },
        "pthread_join"              => { {PthreadT, Pointer(PVoid)}, Int },
        "pthread_mutexattr_destroy" => { {Pointer(PthreadMutexattrT)}, Int },
        "pthread_mutexattr_init"    => { {Pointer(PthreadMutexattrT)}, Int },
        "pthread_mutexattr_settype" => { {Pointer(PthreadMutexattrT), Int}, Int },
        "pthread_mutex_destroy"     => { {Pointer(PthreadMutexT)}, Int },
        "pthread_mutex_init"        => { {Pointer(PthreadMutexT), Pointer(PthreadMutexattrT)}, Int },
        "pthread_mutex_lock"        => { {Pointer(PthreadMutexT)}, Int },
        "pthread_mutex_trylock"     => { {Pointer(PthreadMutexT)}, Int },
        "pthread_mutex_unlock"      => { {Pointer(PthreadMutexT)}, Int },
        "pthread_self"              => {[] of Path, PthreadT},
        "mmap"                      => { {PVoid, SizeT, Int, Int, Int, OffT}, PVoid },
        "mprotect"                  => { {PVoid, SizeT, Int}, Int },
        "munmap"                    => { {PVoid, SizeT}, Int },
        "madvise"                   => { {PVoid, SizeT, Int}, Int },
        "accept"                    => { {Int, Pointer(Sockaddr), Pointer(SocklenT)}, Int },
        "bind"                      => { {Int, Pointer(Sockaddr), SocklenT}, Int },
        "connect"                   => { {Int, Pointer(Sockaddr), SocklenT}, Int },
        "getpeername"               => { {Int, Pointer(Sockaddr), Pointer(SocklenT)}, Int },
        "getsockname"               => { {Int, Pointer(Sockaddr), Pointer(SocklenT)}, Int },
        "getsockopt"                => { {Int, Int, Int, PVoid, Pointer(SocklenT)}, Int },
        "listen"                    => { {Int, Int}, Int },
        "recv"                      => { {Int, PVoid, Int, Int}, SSizeT },
        "recvfrom"                  => { {Int, PVoid, Int, Int, Pointer(Sockaddr), Pointer(SocklenT)}, SSizeT },
        "send"                      => { {Int, PVoid, Int, Int}, SSizeT },
        "sendto"                    => { {Int, PVoid, Int, Int, Pointer(Sockaddr), SocklenT}, SSizeT },
        "setsockopt"                => { {Int, Int, Int, PVoid, SocklenT}, Int },
        "shutdown"                  => { {Int, Int}, Int },
        "socket"                    => { {Int, Int, Int}, Int },
        "socketpair"                => { {Int, Int, Int, StaticArray(Int, 2)}, Int },
        "freeaddrinfo"              => { {Pointer(Addrinfo)}, Void },
        "gai_strerror"              => { {Int}, PChar },
        "getaddrinfo"               => { {PChar, PChar, Pointer(Addrinfo), Pointer(Pointer(Addrinfo))}, Int },
        "getnameinfo"               => { {Pointer(Sockaddr), SocklenT, PChar, SocklenT, PChar, SocklenT, Int}, Int },
        "sched_yield"               => {[] of Path, Int},
        "closedir"                  => { {Pointer(DIR)}, Int },
        "opendir"                   => { {PChar}, Pointer(DIR) },
        "readdir"                   => { {Pointer(DIR)}, Pointer(Dirent) },
        "rewinddir"                 => { {Pointer(DIR)}, Void },
        "__errno_location"          => {[] of Path, PInt},
        "flock"                     => { {Int, FlockOp}, Int },
        "getrusage"                 => { {Int, Pointer(RUsage)}, Int16 },
        "gettimeofday"              => { {Pointer(Timeval), PVoid}, Int },
        "utimes"                    => { {PChar, StaticArray(Timeval, 2)}, Int },
      },
    }

    def self.run_fun(lib_name, fun_name, args, ret_type) : ICObject
      # print_each_fun LibC

      # for each fun-entry: run the corresponding fun-method:
      {% begin %}
        case lib_name
          {% for lib_name, funs in ALL_FUN %}
          when {{lib_name}}
            case fun_name
              {% for fun_name, types in funs %}
                when {{fun_name}} then fun_{{lib_name.id}}_{{fun_name.id}}(args,ret_type)
              {% end %}
            else todo "fun def '#{lib_name}.#{fun_name}'"
            end
          {% end %}
        else todo "fun def '#{lib_name}.#{fun_name}'"
        end
      {% end %}
    end

    macro print_each_fun(lib_name)
      {% for m in lib_name.resolve.methods %}
        {% puts m %}
      {% end %}
    end

    private def self.ic_object_of(ret, size, ret_type) : ICObject
      return IC.nil if ret.nil?
      p = Pointer(Void).malloc size
      p.copy_from pointerof(ret).as(Void*), size
      ICObject.new ret_type, from: p
    end

    # Define a method to bind each fun-method:
    {% for lib_name, funs in ALL_FUN %}
      {% for fun_name, types in funs %}

        private def self.fun_{{lib_name.id}}_{{fun_name.id}}(args : Array(ICObject), ret_type : Type) : ICObject
          # type in StringLiteral mean the type is a va_arg
          # e.g: "printf" => { {PChar, "Long"}, Int }  is `printf(char*, ...)`
          {% if types[0][-1].is_a? StringLiteral %}
            # if va_arg used, we generate the following code (for printf):
            # ```
             # nb_va_arg = args.size - 1
             # bug!("...") if nb_va_arg > 10
             # va_args = uninitialized StaticArray(Long, 10)
             # nb_va_arg.times do |i|
             #   va_args[i] = args[1 + i].as_va_arg!(Long)
             # end
            # ```
            # Because IC cannot know how many va-arg will be used, it will always initialize 10 va-args
            # and fill only the really used va-args at run-time.
            {% va_args_type = types[0][-1].id %}
            {% fixed_arg_len = types[0].size - 1 %}
            nb_va_arg = args.size - {{fixed_arg_len}}
            raise "Too much variadic arguments used on '{{lib_name.id}}.{{fun_name.id}}', IC only support 10 va-args (used: #{nb_va_arg})" if nb_va_arg > 10
            va_args = uninitialized StaticArray({{va_args_type}},10)
            nb_va_arg.times do |i|
              va_args[i] = args[{{fixed_arg_len}} + i].as_va_arg!({{va_args_type}})
            end
          {% end %}

          # if `fun_name` returns `Void`, generate:
          # ```
          # ret = nil
          # LibName.fun_name(args[0].as!(Arg0Type), args[1].as!(Arg1Type), ...)
          # ```
          # else, generate:
          # ```
          # ret = LibName.fun_name(args[0].as!(Arg0Type), args[1].as!(Arg1Type), ...)
          # ```
          {% if types[1].stringify == "Void" %}
            ret = nil
          {% else %}
            ret =
          {% end %}
            {{lib_name.id}}.{{fun_name.id}}({{*types[0].map_with_index do |t, i|
                                                if t.is_a? StringLiteral
                                                  # if the argument is a va-arg, use all ten va-args
                                                  "va_args[0], va_args[1], va_args[2], va_args[3], va_args[4], va_args[5], va_args[6], va_args[7], va_args[8], va_args[9]".id
                                                else
                                                  "args[#{i}].as!(#{t.id})".id
                                                end
                                              end}})
          ic_object_of(ret, sizeof({{types[1]}}), ret_type)
        end
      {% end %}
    {% end %}
  end
end

module IC
  def self.run_fun_body(receiver, a_def, args, ret_type) : ICObject
    if receiver.nil?
      todo "top level fun '#{a_def.real_name}'"
    else
      type = receiver.type
      bug! "Trying to call a fun def on a non-LibType" if !type.is_a? Crystal::LibType

      IC::FunPrimitives.run_fun type.name, a_def.real_name, args, ret_type
    end
  end

  class ICObject
    def as!(type : T.class) : T forall T
      v = @raw.as(T*).value
      pp! v
      v
    end

    def as_va_arg!(type : T.class) : T forall T
      v = self.as!(T)
      mask = (1u64 << @type.ic_size*8) &- 1u64
      v & mask
    end
  end
end
