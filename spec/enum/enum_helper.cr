IC.parse(<<-'CODE').run

  enum BasicEnum
    A
    B
    C
    D = B+2*C
    E = D*C - (C|D)
  end

  @[Flags]
  enum FlagsEnum
    A
    B
    C
    D
    E
  end

  enum TypedEnum : UInt8
    A = 4
    B
    C
  end

  def enum_func(x : BasicEnum, *args : BasicEnum, **options : BasicEnum)
    {x, args, options}
  end

  CODE