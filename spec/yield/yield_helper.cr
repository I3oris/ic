IC.parse(<<-'CODE').run

  def yield_func1(*args)
    yield args
  end

  def yield_func2(a)
    b = a
    yield_func1(31) do |a|
      yield a[0] + b
    end
  end

  def yield_func3(a, b)
    (yield a+b)+(yield(yield a*2))
  end

  def yield_func4(a, b)
    x = yield a + b, b
    y = yield x, a
    x + y
  end

  def yield_func5(x)
    while x < yield 0
      x += yield x
      break if x > 10000
    end
    yield (-1 + x)
  end

  def times_func(n)
    i = 0
    while i < n
      yield i
      i += 1
    end
  end
  CODE
