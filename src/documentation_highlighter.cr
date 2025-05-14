require "markd"

class IC::DocumentationHighlighter
  alias Node = Markd::Node

  @highlighter = IC::Highlighter.new
  @io = String::Builder.new

  def self.highlight(text, toggle = true)
    self.new.highlight(text, toggle: toggle)
  end

  def highlight(text : String, toggle = true)
    return text unless toggle
    return "" if text.empty?

    document = Markd::Parser.parse(text)
    render(document)
    @io.to_s
  end

  private def render(node : Node)
    case node.type
    in .document?       then document(node)
    in .heading?        then heading(node)
    in .code?           then code(node)
    in .code_block?     then code_block(node)
    in .paragraph?      then paragraph(node)
    in .text?           then text(node)
    in .soft_break?     then soft_break(node)
    in .emphasis?       then emphasis(node)
    in .strong?         then strong(node)
    in .list?           then list(node)
    in .item?           then item(node)
    in .html_block?     then html_block(node)
    in .html_inline?    then html_inline(node)
    in .image?          then image(node)
    in .link?           then link(node)
    in .block_quote?    then block_quote(node)
    in .thematic_break? then thematic_break(node)
    in .line_break?     then nil
    in .custom_in_line? then nil
    in .custom_block?   then nil
    end

    render(node.next?)
  end

  private def render(node : Nil)
  end

  private def document(node)
    render(node.first_child?)
  end

  # Display markdown header like the following:
  #
  # `# level 1`:
  # ╔═════════════════════════════════════╗
  # ║                title                ║
  # ╚═════════════════════════════════════╝
  #
  # Or
  # ═══════════════════════════════════════
  # loooooooooooooooooooooooooooooooooooooo
  # oooong_title
  # ═══════════════════════════════════════
  #
  # `## level 2`:
  # ► title
  # ═══════════════════════════════════════
  #
  # `### level 3`:
  # ► title
  # ━━━━━━━━
  #
  # `#### level 4`:
  # ► title
  private def heading(node)
    level = node.data["level"].as(Int32)
    title = render_on_string(node.first_child?).chomp('\n')

    width = Reply::Term::Size.width
    case level
    when 1
      if title.size < width - 2
        @io << '╔' << "═"*(width - 2) << '╗'
        @io << '║' << title.center(width - 2).colorize.bold << '║'
        @io << '╚' << "═"*(width - 2) << '╝'
      else
        @io << "═"*width
        @io << title << '\n'
        @io << "═"*width
      end
    when 2
      @io << "► " << title << '\n'
      @io << "═"*width
    when 3
      @io << "► " << title << '\n'
      @io << "━"*{title.size + 3, width}.min << '\n'
    else
      @io << "► " << title << '\n'
    end
    @io << '\n'
  end

  private def code(node)
    @io << @highlighter.highlight(node.text)
  end

  # Display markdown code block like the following:
  #
  # ╭───────╮
  # │def foo│
  # │  42   │
  # │end    │
  # ╰───────╯
  #
  # Or
  # ─────────────────────────────────────────────────
  # def loooooooooooooooooooooooooooooooooooooooooooo
  # ooooooong
  #   42
  # end
  # ─────────────────────────────────────────────────
  private def code_block(node)
    languages = node.fence_language || ""
    width = Reply::Term::Size.width

    lines = node.text.strip('\n').split('\n')
    max_width = lines.max_of &.size
    if max_width > width - 3
      overflow = true
      max_width = width - 3
    end

    lines = lines.map &.ljust(max_width)
    if languages != "text"
      lines = @highlighter.highlight(lines.join('\n')).split('\n')
    end

    if overflow
      @io << "─"*width
      lines.each { |line| @io << line << '\n' }
      @io << "─"*width
    else
      @io << '╭' << "─"*max_width << '╮' << '\n'
      lines.each do |line|
        @io << '│' << line << '│' << '\n'
      end
      @io << '╰' << "─"*max_width << '╯' << '\n'
    end

    @io << '\n'
  end

  private def paragraph(node)
    render(node.first_child?)
    @io << '\n' << '\n'
  end

  private def text(node)
    @io << node.text
  end

  private def soft_break(node)
    @io << ' '
  end

  private def emphasis(node)
    @io << render_on_string(node.first_child?).colorize.italic
  end

  private def strong(node)
    @io << render_on_string(node.first_child?).colorize.bold
  end

  private def list(node)
    render(node.first_child?)
  end

  private def item(node)
    @io << "• "
    render(node.first_child?)
  end

  private def block_quote(node)
    content = render_on_string(node.first_child?)
    content.each_line do |line|
      @io << "│ " << line << '\n'
    end
    @io << '\n'
  end

  private def html_block(node)
    @io.puts node.text
    @io << '\n'
  end

  private def html_inline(node)
    @io.puts node.text
    @io << '\n'
  end

  private def image(node)
    text = render_on_string(node.first_child?)
    dest = node.data["destination"].as(String)
    @io << "![#{text}](#{dest})"
  end

  private def link(node)
    text = render_on_string(node.first_child?)
    dest = node.data["destination"].as(String)
    @io << "[#{text}](#{dest})"
  end

  private def thematic_break(node)
    width = Reply::Term::Size.width
    @io << "─"*width << '\n'
  end

  private def render_on_string(node)
    String.build do |string_io|
      io_tmp = @io
      @io = string_io
      render(node)
      @io = io_tmp
    end
  end
end
