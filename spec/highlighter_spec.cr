describe IC::Highlighter do
  it "highlight object result" do
    IC::Highlighter.highlight(" => #<Foo:0x7f741b3a2000 @x=0 @y=0>").should eq \
      " \e[91m=>\e[0m \e[90;1m#<\e[0m\e[90;1mFoo\e[0m\e[90;1m:\e[0m\e[90;1m0x7f741b3a2000\e[0m\e[90;1m \e[0m\e[90;1m@x\e[0m\e[90;1m=\e[0m\e[90;1m0\e[0m\e[90;1m \e[0m\e[90;1m@y\e[0m\e[90;1m=\e[0m\e[90;1m0\e[0m\e[90;1m>\e[0m\e[m"
  end

  it "highlight proc result" do
    IC::Highlighter.highlight(" => #<Proc(Int32):0x7f107040ebf0:closure").should eq \
      " \e[91m=>\e[0m \e[90;1m#<\e[0m\e[90;1mProc\e[0m\e[90;1m(\e[0m\e[90;1mInt32\e[0m\e[90;1m)\e[0m\e[90;1m:\e[0m\e[90;1m0x7f107040ebf0\e[0m\e[90;1m:closure\e[0m\e[m"
  end

  it "highlight object in array result" do
    IC::Highlighter.highlight(" => [#<Foo:0x7f5f64d5de00 @x=#<Proc(Int32):0x7f5f5fc4a4c0>>, 42]").should eq \
      " \e[91m=>\e[0m [\e[90;1m#<\e[0m\e[90;1mFoo\e[0m\e[90;1m:\e[0m\e[90;1m0x7f5f64d5de00\e[0m\e[90;1m \e[0m\e[90;1m@x\e[0m\e[90;1m=\e[0m\e[90;1m#<\e[0m\e[90;1mProc\e[0m\e[90;1m(\e[0m\e[90;1mInt32\e[0m\e[90;1m)\e[0m\e[90;1m:\e[0m\e[90;1m0x7f5f5fc4a4c0\e[0m\e[90;1m>\e[0m\e[90;1m>\e[0m, \e[35m42\e[0m]\e[m"
  end

  it "highlight nested objects result" do
    IC::Highlighter.highlight(%( => ["foo", #<Foo:0x7f4b9c47c880 @y=#<Foo:0x7f4b9c47c940 @y=0, @x=[1, 2, 3], @z='z', @t=/regex/>, @x=[1, 2, 3], @z='z', @t=/regex/>, 'x', {"foo" => #<Proc(Int32):0x7f4b9c453f40>, "bar" => :baz}, 31])).should eq \
      " \e[91m=>\e[0m [\e[93m\"\e[0m\e[93mfoo\e[0m\e[93m\"\e[0m, \e[90;1m#<\e[0m\e[90;1mFoo\e[0m\e[90;1m:\e[0m\e[90;1m0x7f4b9c47c880\e[0m\e[90;1m \e[0m\e[90;1m@y\e[0m\e[90;1m=\e[0m\e[90;1m#<\e[0m\e[90;1mFoo\e[0m\e[90;1m:\e[0m\e[90;1m0x7f4b9c47c940\e[0m\e[90;1m \e[0m\e[90;1m@y\e[0m\e[90;1m=\e[0m\e[90;1m0\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m@x\e[0m\e[90;1m=\e[0m\e[90;1m[\e[0m\e[90;1m1\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m2\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m3\e[0m\e[90;1m]\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m@z\e[0m\e[90;1m=\e[0m\e[90;1m'z'\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m@t\e[0m\e[90;1m=\e[0m\e[90;1m/\e[0m\e[90;1mregex\e[0m\e[90;1m/\e[0m\e[90;1m>\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m@x\e[0m\e[90;1m=\e[0m\e[90;1m[\e[0m\e[90;1m1\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m2\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m3\e[0m\e[90;1m]\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m@z\e[0m\e[90;1m=\e[0m\e[90;1m'z'\e[0m\e[90;1m,\e[0m\e[90;1m \e[0m\e[90;1m@t\e[0m\e[90;1m=\e[0m\e[90;1m/\e[0m\e[90;1mregex\e[0m\e[90;1m/\e[0m\e[90;1m>\e[0m, \e[93m'x'\e[0m, {\e[93m\"\e[0m\e[93mfoo\e[0m\e[93m\"\e[0m \e[91m=>\e[0m \e[90;1m#<\e[0m\e[90;1mProc\e[0m\e[90;1m(\e[0m\e[90;1mInt32\e[0m\e[90;1m)\e[0m\e[90;1m:\e[0m\e[90;1m0x7f4b9c453f40\e[0m\e[90;1m>\e[0m, \e[93m\"\e[0m\e[93mbar\e[0m\e[93m\"\e[0m \e[91m=>\e[0m \e[35m:baz\e[0m}, \e[35m31\e[0m]\e[m"
  end

  it "fixes #12" do
    IC::Highlighter.highlight(%( => {"help" => Procodile::CliCommand(@name="help", @description="Shows this help output", @options=nil, @callable=#<Proc(Nil):0x7f2fd9a5f600:closure>), "kill" => Procodile::CliCommand(@name="kill", @description="Forcefully kill all known processes", @options=nil, @callable=#<Proc(Nil):0x7f2fd9afe780:closure>), "start" => Procodile::CliCommand(@name="start", @description="Starts processes and/or the supervisor", @options=nil, @callable=#<Proc(Nil):0x7f2fd770da00:closure>)})).should eq \
      " \e[91m=>\e[0m {\e[93m\"\e[0m\e[93mhelp\e[0m\e[93m\"\e[0m \e[91m=>\e[0m \e[34;4mProcodile\e[0m\e[34;4m::\e[0m\e[34;4mCliCommand\e[0m(@name\e[91m=\e[0m\e[93m\"\e[0m\e[93mhelp\e[0m\e[93m\"\e[0m, @description\e[91m=\e[0m\e[93m\"\e[0m\e[93mShows this help output\e[0m\e[93m\"\e[0m, @options\e[91m=\e[0m\e[36;1mnil\e[0m, @callable\e[91m=\e[0m\e[90;1m#<\e[0m\e[90;1mProc\e[0m\e[90;1m(\e[0m\e[90;1mNil\e[0m\e[90;1m)\e[0m\e[90;1m:\e[0m\e[90;1m0x7f2fd9a5f600\e[0m\e[90;1m:closure\e[0m\e[90;1m>\e[0m), \e[93m\"\e[0m\e[93mkill\e[0m\e[93m\"\e[0m \e[91m=>\e[0m \e[34;4mProcodile\e[0m\e[34;4m::\e[0m\e[34;4mCliCommand\e[0m(@name\e[91m=\e[0m\e[93m\"\e[0m\e[93mkill\e[0m\e[93m\"\e[0m, @description\e[91m=\e[0m\e[93m\"\e[0m\e[93mForcefully kill all known processes\e[0m\e[93m\"\e[0m, @options\e[91m=\e[0m\e[36;1mnil\e[0m, @callable\e[91m=\e[0m\e[90;1m#<\e[0m\e[90;1mProc\e[0m\e[90;1m(\e[0m\e[90;1mNil\e[0m\e[90;1m)\e[0m\e[90;1m:\e[0m\e[90;1m0x7f2fd9afe780\e[0m\e[90;1m:closure\e[0m\e[90;1m>\e[0m), \e[93m\"\e[0m\e[93mstart\e[0m\e[93m\"\e[0m \e[91m=>\e[0m \e[34;4mProcodile\e[0m\e[34;4m::\e[0m\e[34;4mCliCommand\e[0m(@name\e[91m=\e[0m\e[93m\"\e[0m\e[93mstart\e[0m\e[93m\"\e[0m, @description\e[91m=\e[0m\e[93m\"\e[0m\e[93mStarts processes and/or the supervisor\e[0m\e[93m\"\e[0m, @options\e[91m=\e[0m\e[36;1mnil\e[0m, @callable\e[91m=\e[0m\e[90;1m#<\e[0m\e[90;1mProc\e[0m\e[90;1m(\e[0m\e[90;1mNil\e[0m\e[90;1m)\e[0m\e[90;1m:\e[0m\e[90;1m0x7f2fd770da00\e[0m\e[90;1m:closure\e[0m\e[90;1m>\e[0m)}\e[m"
  end
end
