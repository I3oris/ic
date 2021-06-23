describe :string do
  it "creates empty string" do
    IC.run_spec(%("")).should eq %("")
  end

  it "adds string" do
    IC.run_spec(%("Hello "+"World"+"!")).should eq %("Hello World!")
  end
end

describe :array do
  it "fetch" do
    IC.run_spec(%([0,42,5][1])).should eq %(42)
  end

  it "supports many types'" do
    IC.run_spec(%([0,:foo,"bar"][1])).should eq %(:foo)
  end
end