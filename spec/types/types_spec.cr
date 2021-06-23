describe Crystal::Type do
  it "describes Nil" do
    IC.program.nil.reference?.should eq false
    IC.program.nil.ic_size.should eq 0
    IC.program.nil.copy_size.should eq 8
  end

  it "describes Int32" do
    IC.program.int32.reference?.should eq false
    IC.program.int32.ic_size.should eq 4
    IC.program.int32.copy_size.should eq 4
  end

  it "describes String" do
    IC.program.string.reference?.should eq true
    IC.program.string.ic_size.should eq 8
    IC.program.string.copy_size.should eq 8
    IC.program.string.ic_class_size.should eq 16
  end
end