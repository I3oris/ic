require "spec"
require "./ic_spec_helper"

describe IC::ReplInterface::History do
  it "submits entry" do
    history = IC::Spec.empty_history
    entries = IC::Spec.history_entries

    IC::Spec.verify_history(history, [] of Array(String), index: 0)

    history << [%(puts "Hello World")]
    IC::Spec.verify_history(history, entries[0...1], index: 1)

    history << [%(i = 0)]
    IC::Spec.verify_history(history, entries[0...2], index: 2)

    history << [
      %(while i < 10),
      %(  puts i),
      %(  i += 1),
      %(end),
    ]
    IC::Spec.verify_history(history, entries, index: 3)
  end

  it "submit dupplicate entry" do
    history = IC::Spec.history
    entries = IC::Spec.history_entries

    IC::Spec.verify_history(history, entries, index: 3)

    history << [%(i = 0)]
    IC::Spec.verify_history(history, [entries[0], entries[2], entries[1]], index: 3)
  end

  it "clears" do
    history = IC::Spec.history
    IC::Spec.verify_history(history, IC::Spec.history_entries, index: 3)

    history.clear
    IC::Spec.verify_history(history, [] of Array(String), index: 0)
  end

  it "navigates" do
    history = IC::Spec.history
    entries = IC::Spec.history_entries

    IC::Spec.verify_history(history, entries, index: 3)

    # Before down: current edition...
    # After down: current edition...
    history.down(["current edition..."]) do
      raise "Should not yield"
    end.should be_nil
    IC::Spec.verify_history(history, entries, index: 3)

    # Before up: current edition...
    # After up: while i < 10
    #  puts i
    #  i += 1
    # end
    history.up(["current edition..."]) do |entry|
      entry
    end.should eq entries[2]
    IC::Spec.verify_history(history, entries, index: 2)

    # Before up: while i < 10
    #  puts i
    #  i += 1
    # end
    # After up: i = 0
    history.up(entries[2]) do |entry|
      entry
    end.should eq entries[1]
    IC::Spec.verify_history(history, entries, index: 1)

    # Before up (edited): edited_i = 0
    # After up: puts "Hello World"
    history.up([%(edited_i = 0)]) do |entry|
      entry
    end.should eq entries[0]
    IC::Spec.verify_history(history, entries, index: 0)

    # Before up: puts "Hello World"
    # After up: puts "Hello World"
    history.up(entries[0]) do
      raise "Should not yield"
    end.should be_nil
    IC::Spec.verify_history(history, entries, index: 0)

    # Before down: puts "Hello World"
    # After down: edited_i = 0
    history.down(entries[0]) do |entry|
      entry
    end.should eq [%(edited_i = 0)]
    IC::Spec.verify_history(history, entries, index: 1)

    # Before down down: edited_i = 0
    # After down down: current edition...
    history.down([%(edited_i = 0)], &.itself).should eq entries[2]
    history.down(entries[2], &.itself).should eq [%(current edition...)]
    IC::Spec.verify_history(history, entries, index: 3)
  end
end
