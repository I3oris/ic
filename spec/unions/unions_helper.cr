IC.run_file IC::PRELUDE_PATH

IC.parse(<<-'CODE').run

  module UnionModule
    def f
      :UnionModule
    end
  end

  module UnionSubModule
    include UnionModule
    def f
      :UnionSubModule
    end
  end

  class UnionClass
    def f
      :UnionClass
    end
  end

  class UnionSubClass1 < UnionClass
    def f
      :UnionSubClass1
    end
  end

  class UnionSubClass2 < UnionClass
  end

  class UnionSubSubClass < UnionSubClass1
    include UnionSubModule
  end

  struct UnionStruct
    @x = :foo
    @y = 3.14
  end

  class UnionIvars
    @union_values : Int32|UnionStruct|Nil = nil
    @union_reference_like : UnionClass|String|Nil = nil
    @union_mixed : UnionStruct|UnionClass|Nil = nil

    property union_values, union_reference_like, union_mixed

    def all
      {@union_values, @union_reference_like, @union_mixed}
    end
  end
  CODE