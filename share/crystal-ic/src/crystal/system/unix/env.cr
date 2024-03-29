require "c/stdlib"

module Crystal::System::Env
  # Sets an environment variable.
  def self.set(key : String, value : String) : Nil
    key.check_no_null_byte("key")
    value.check_no_null_byte("value")

    if LibC.setenv(key, value, 1) != 0
      raise RuntimeError.from_errno("setenv")
    end
  end

  # Unsets an environment variable.
  def self.set(key : String, value : Nil) : Nil
    key.check_no_null_byte("key")

    if LibC.unsetenv(key) != 0
      raise RuntimeError.from_errno("unsetenv")
    end
  end

  # Gets an environment variable.
  def self.get(key : String) : String?
    key.check_no_null_byte("key")

    if value = LibC.getenv(key)
      String.new(value)
    end
  end

  # Returns `true` if environment variable is set.
  def self.has_key?(key : String) : Bool
    key.check_no_null_byte("key")

    !!LibC.getenv(key)
  end

  # Iterates all environment variables.
  def self.each(&block : String, String ->)
    environ_ptr = LibC.environ
    while environ_ptr
      environ_value = environ_ptr.value
      if environ_value
        # this does `String.new(environ_value).partition('=')` without an intermediary string
        key_value = Slice.new(environ_value, LibC.strlen(environ_value))
        split_index = key_value.index!(0x3d_u8) # '='
        key = String.new(key_value[0, split_index])
        value = String.new(key_value[split_index + 1..])
        yield key, value
        environ_ptr += 1
      else
        break
      end
    end
  end
end
