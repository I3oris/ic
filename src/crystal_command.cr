# Redefine the Exit enum in "compiler/crystal/command.cr"
# We can require "compiler/crystal/command.cr" because this will add the unnecessary dependency "sanitize".

class Crystal::Command
  enum Exit
    # Successful exit
    OK = 0

    # Expected failure
    FAILURE = 1

    # User error (e.g. wrong CLI argument)
    USAGE_ERROR = 1

    # Code error (e.g. invalid source code)
    CODE_ERROR = 1

    # Internal compiler error
    SOFTWARE_ERROR = 1
  end
end
