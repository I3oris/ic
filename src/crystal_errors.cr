# NOTE: This class definition should be placed before the re-opoening of module ErrorFormat.
class Crystal::TopLevelExpressionVirtualFile < Crystal::VirtualFile
  # The line number where this top-level expression starts
  getter initial_line_number

  def initialize(source : String, @initial_line_number : Int32 = 0)
    super(Macro.new(""), source, expanded_location: Location.new("", line_number: initial_line_number, column_number: 0))
  end

  def to_s(io)
    # Don't display 'expanded macro: <macro-name>'
    io << "<top-level>"
  end
end

module Crystal::ErrorFormat
  def format_macro_error(top_level_expression : TopLevelExpressionVirtualFile)
    formatted_error = format_error(
      filename: "<top-level>",
      lines: top_level_expression.source.split('\n'),
      line_number: @line_number,
      line_number_offset: top_level_expression.initial_line_number,
      column_number: @column_number,
      size: @size
    )
    "In #{formatted_error}"
  end

  # From compiler/crystal/exception.cr: (adding line_number_offset)
  def format_error(filename, lines, line_number, column_number, size = 0, line_number_offset = 0)
    return "#{relative_filename(filename)}" unless line_number

    unless line = lines[line_number - 1]?
      return filename_row_col_message(filename, line_number + line_number_offset, column_number)
    end
    line_number += line_number_offset

    String.build do |io|
      case filename
      in String
        io << filename_row_col_message(filename, line_number, column_number)
      in VirtualFile
        io << "macro '" << colorize("#{filename.macro.name}").underline << '\''
      in Nil
        io << "unknown location"
      end

      decorator = line_number_decorator(line_number)
      lstripped_line = line.lstrip
      space_delta = line.chars.size - lstripped_line.chars.size
      # Column number should start at `1`. We're using `0` to track bogus passed
      # `column_number`.
      final_column_number = (column_number - space_delta).clamp(0..)

      io << "\n\n"
      io << colorize(decorator).dim << colorize(lstripped_line.chomp).bold
      append_error_indicator(io, decorator.chars.size, final_column_number, size || 0)
    end
  end
end
