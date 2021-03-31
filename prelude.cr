{% for type in %w(Int32 UInt64) %}
  struct {{type.id}}
    {% for op in %w(+ - * == != <= >= < >) %}
      @[Primitive(:binary)]
      def {{op.id}}(other : {{type.id}}) : self
      end
    {% end %}
  end
{% end %}

class Object
  @[Primitive(:class)]
  def class
  end

  # :nodoc:
  @[Primitive(:object_crystal_type_id)]
  def crystal_type_id : Int32
  end

  macro getter(*names)
    {% for n in names %}
      def {{n.id}}
        @{{n.id}}
      end
    {% end %}
  end

  macro setter(*names)
    {% for n in names %}
      def {{n.id}}=(@{{n.id}})
      end
    {% end %}
  end

  macro property(*names)
    getter {{*names}}
    setter {{*names}}
  end
end

class Reference
  @[Primitive(:object_id)]
  def object_id : UInt64
  end
end

class Class
  @[Primitive(:class_crystal_instance_type_id)]
  def crystal_instance_type_id : Int32
  end
end

## ??? not in stdlib?
@[Primitive(:allocate)]
def allocate
end