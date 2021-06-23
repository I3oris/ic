IC.parse(<<-'CODE').run
  class IvarsClass
    @foo = :foo
    @bar : String?

    property foo, bar
  end

  class IvarsSubClass < IvarsClass
    @baz : Int32|IvarsClass = 7

    property baz
  end

  class IvarsGenericClass(T, U) < IvarsClass
    @t : T|{T, U}?

    property t
  end

  class CvarsClass
    @@c_foo : Symbol?
    @@c_bar = "bar"

    class_property c_foo, c_bar
  end

  class CvarsSubClass1 < CvarsClass
    @@c_bar = "sub_bar"
  end

  class CvarsSubClass2 < CvarsClass
    @@c_foo : Symbol?
  end
  CODE