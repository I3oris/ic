IC.parse(<<-'CODE').run

  class PrimitivesClass
    @x = 0
    @y = ""
  end

  class PrimitivesSubClass < PrimitivesClass
    @z = :foo
  end

  struct PrimitivesStruct
    @x = 0
    @y = ""
    @z = :foo
  end

  enum PrimitivesEnum
    A
    B
    C
  end
  CODE
