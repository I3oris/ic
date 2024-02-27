module Crystal
  # All methods overwritten here directly copied from share/crystal-ic/src/compiler/crystal/crystal_path.cr,
  # and updated for checking FileStorage
  struct CrystalPath
    private def add_target_path(codegen_target)
      target = "#{codegen_target.architecture}-#{codegen_target.os_name}"

      @entries.each do |path|
        path = File.join(path, "lib_c", target)
        if Dir.exists?(path) || FileStorage.files.map(&.path).any?(&.starts_with?(path))
          @entries << path unless @entries.includes?(path)
          return
        end
      end
    end

    private def find_in_path_relative_to_dir(filename, relative_to)
      return unless relative_to.is_a?(String)

      # Check if it's a wildcard.
      if filename.ends_with?("/*") || (recursive = filename.ends_with?("/**"))
        filename_dir_index = filename.rindex!('/')
        filename_dir = filename[0..filename_dir_index]
        relative_dir = "#{relative_to}/#{filename_dir}".gsub("/./", "/")
        relative_dir = "/#{relative_dir}" unless relative_dir.starts_with?("/")

        if File.exists?(relative_dir)
          files = [] of String
          gather_dir_files(relative_dir, files, recursive)
          return files
        end

        if FileStorage.files.map(&.path).any?(&.starts_with?(relative_dir))
          files = [] of String
          FileStorage.files.map(&.path).each do |path|
            if filename.ends_with?("/**")
              files << path if path.starts_with?(relative_dir)
            else
              files << path if path.starts_with?(relative_dir) && (path =~ /#{relative_dir}[^\/]+.cr/)
            end
          end
          return files
        end

        return nil
      end

      each_file_expansion(filename, relative_to) do |path|
        absolute_path = File.expand_path(path, dir: @current_dir)
        return absolute_path if File.file?(absolute_path) || FileStorage.get?(absolute_path)
      end

      nil
    end
  end
end
