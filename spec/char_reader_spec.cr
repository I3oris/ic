require "spec"
require "./ic_spec_helper"

describe IC::ReplInterface::CharReader do
  it "read chars" do
    IC::Spec.verify_read_char('a', expect: ['a', :exit])
    IC::Spec.verify_read_char("Hello", expect: ["Hello", :exit])
  end

  it "read ANSI escape sequence" do
    IC::Spec.verify_read_char("\e[A", expect: [:up, :exit])
    IC::Spec.verify_read_char("\e[B", expect: [:down, :exit])
    IC::Spec.verify_read_char("\e[C", expect: [:right, :exit])
    IC::Spec.verify_read_char("\e[D", expect: [:left, :exit])
    IC::Spec.verify_read_char("\e[3~", expect: [:delete, :exit])
    IC::Spec.verify_read_char("\e[1;5A", expect: [:ctrl_up, :exit])
    IC::Spec.verify_read_char("\e[1;5B", expect: [:ctrl_down, :exit])
    IC::Spec.verify_read_char("\e[1;5C", expect: [:ctrl_right, :exit])
    IC::Spec.verify_read_char("\e[1;5D", expect: [:ctrl_left, :exit])

    IC::Spec.verify_read_char("\e\t", expect: [:shift_tab, :exit])
    IC::Spec.verify_read_char("\e\r", expect: [:insert_new_line, :exit])
    IC::Spec.verify_read_char("\e", expect: [:escape, :exit])
    IC::Spec.verify_read_char("\n", expect: [:enter, :exit])

    IC::Spec.verify_read_char('\0', expect: [:exit])
    IC::Spec.verify_read_char('\u0001', expect: [:move_cursor_to_begin, :exit])
    IC::Spec.verify_read_char('\u0003', expect: [:keyboard_interrupt, :exit])
    IC::Spec.verify_read_char('\u0004', expect: [:exit])
    IC::Spec.verify_read_char('\u0005', expect: [:move_cursor_to_end, :exit])
    IC::Spec.verify_read_char('\u0018', expect: [:exit])
    IC::Spec.verify_read_char('\u007F', expect: [:back, :exit])
  end

  it "read large buffer" do
    IC::Spec.verify_read_char(
      "a"*10_000,
      expect: ["a" * 1024]*9 + ["a"*(10_000 - 9*1024), :exit]
    )
  end
end
