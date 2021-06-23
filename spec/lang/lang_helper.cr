IC.parse(<<-'CODE').run

  class LangGenericClass(X,Y,Z)
    def self.type_vars
      {X, Y, Z}
    end
  end

  def set_global(value)
    $~ = value
  end

  CODE