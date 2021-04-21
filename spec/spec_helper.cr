require "spec"
require "../src/icr"

module ICR
  def self.running_spec?
    true
  end
end

ICR.parse(<<-'CODE').run
  class SpecClass
    property x
    property y
    property name

    def initialize(@x = 0, @y = 0, @name = "unnamed")
    end
  end

  class SpecSubClass1 < SpecClass
    @bar = "foo"
    property bar
  end

  class SpecSubClass2 < SpecClass
    @baz = :baz
    property baz
  end

  # class SpecSubSubClass < SpecSubClass1
  #   @bam = :bam
  #   property bam
  # end

  struct SpecStruct
    property x
    property y
    property name

    def initialize(@x = 0, @y = 0, @name = "unnamed")
    end
  end

  class SpecUnionIvars
    @union_values : Int32|SpecStruct|Nil = nil
    @union_reference_like : SpecClass|String|Nil = nil
    @union_mixed : SpecStruct|SpecClass|Nil = nil

    property union_values, union_reference_like, union_mixed

    def all
      {@union_values, @union_reference_like, @union_mixed}
    end
  end

  CODE