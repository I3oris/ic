module IC::REPLInterface::Term
  module Size
    lib C
      struct WinSize
        row : UInt16
        col : UInt16
        x_pixel : UInt16
        y_pixel : UInt16
      end

      TIOCGWINSZ = 21523 # Magic number.

      fun ioctl(fd : Int32, request : UInt32, winsize : C::WinSize*) : Int32
    end

    # Gets the terminals width
    def self.size : {Int32, Int32}
      C.ioctl(0, C::TIOCGWINSZ, out screen_size)
      {screen_size.col.to_i32, screen_size.col.to_i32}
    end

    def self.width
      size[0]
    end

    def self.height
      size[1]
    end
  end
end
