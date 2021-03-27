struct Int32
  {% for op in %w(+ - * == != <= >= < >) %}
    @[Primitive(:binary)]
    def {{op.id}}(other : Int32) : self
    end
  {% end %}
end

struct Int32
  def add(other)
    self + other
  end

  def foo(a, b)
    a = 0
    tmp = self.add(a)
    tmp.add(b)
  end
end

x = 42
while true
  x = 5
  break if x == 5
end
x
# x.foo x,3
# x = "42"
