IC.parse(<<-'CODE').run

  def proc_call(p, x_, y_)
    p.call x_, y_
  end

  def proc_closure_in_def(x)
    ->{x}
  end
  CODE
