require "compiler/crystal/*"
require "compiler/crystal/codegen/*"
require "compiler/crystal/macros/*"
require "compiler/crystal/semantic/*"
require "./objects"
require "./nodes"
require "./primitives"
require "./highlighter"
require "./shell"
require "colorize"
require "term-reader"
# require "compiler/crystal/syntax"
# abstract class ModuleType < NamedType
#   getter defs : Hash(String, Array(DefWithMetadata))?
#   getter macros : Hash(String, Array(Macro))?
#   getter hooks : Array(Hook)?
#   getter(parents) { [] of Type }
# end
ICR.run_file "./program.cr"
ICR.run3

def raise_error(arg)
  ::raise arg
end

module ICR
  VERSION = "0.1.0"

  class_property program = Crystal::Program.new
  class_property args_context = [{} of String => ICRObject]
  class_property receiver_context = [] of ICRObject
  class_property type_context = [] of Crystal::Type

  def self.parse(text)
    ast_node = Crystal::Parser.parse text
    ast_node = @@program.normalize(ast_node)
    ast_node = @@program.semantic(ast_node)
    ast_node
  end

  def self.run_file(path)
    final = ICR.parse(File.read(path)).run
    puts "# => #{final.get_value.inspect}"
  end

  @@result : ICRObject? = nil

  def self.display_result
    if r = @@result
      puts "# => #{r.get_value.inspect}"
    end
  end

  def self.run3
    code = ""
    last_ast_node = nil

    Shell.new.run(->self.display_result) do |line, multiline|
      error = false
      if !multiline.empty?
        multiline += line
        ast_node = ICR.parse(code + "\n" + multiline)
        run_last_expression(expressionize(last_ast_node), expressionize(ast_node))
        last_ast_node = ast_node
        code += "\n" + multiline
        # if multiline.split("\n").size >= 5
        #   # @@result = "multiline: #{multiline}"
        # else
        #   @@result = nil
        #   error = true
        # end
      else
        ast_node = ICR.parse(code + "\n" + line)
        run_last_expression(expressionize(last_ast_node), expressionize(ast_node))
        last_ast_node = ast_node
        code += "\n" + line

        # if line.starts_with? "def"
        #   @@result = nil
        #   error = true
        # else
        #   @@result = "line: #{line}"
        # end
      end
      :line
    rescue e
      @@result = nil
      if is_incomplet(e)
        # program += "\n"+l
        # prompt :special
        # next
        :multiline
      else
        puts
        puts e.message.colorize.yellow.bold
        :error
        # puts e
        # prompt
      end
      # error
    end
  end

  def self.run
    program = ""
    last_ast_node = nil
    highlighter = ICR::Highlighter.new ""
    STDIN.each_line do |l|
      if l.empty?
        prompt
        next
      end
      ast_node = ICR.parse(program + "\n" + l)
      run_last_expression(expressionize(last_ast_node), expressionize(ast_node))
      last_ast_node = ast_node
      program += "\n" + l
      puts highlighter.highlight(Crystal.format(program))
      prompt :normal
    rescue e
      if is_incomplet(e)
        program += "\n" + l
        prompt :special
        next
      else
        puts e
        prompt
      end
    end
  end

  private def self.expressionize(node)
    if node.is_a? Crystal::Expressions
      node
    elsif node.nil?
      Crystal::Expressions.new
    else
      e = Crystal::Expressions.new
      e.expressions << node
      e
    end
  end

  private def self.run_last_expression(last_ast_node, ast_node)
    # final =
    #   if ast_node.is_a? Crystal::Expressions
    #     ast_node.expressions[-1].run
    #   else
    #     ast_node.run
    #   end
    l_size = last_ast_node.expressions.size
    size = ast_node.expressions.size
    if l_size != size
      final = ast_node.expressions[l_size..].map(&.run)[-1]
      @@result = final
      # ast_node = ast_node.expressions[-1] if ast_node.is_a?(Crystal::Expressions)
      # if last_ast_node
      #   last_ast_node = last_ast_node.expressions[] responds_to?
      # else
      #   final = ast_node.run
      #   puts "# => #{final.get_value.inspect}"
      # end
    end
  end

  private def self.is_incomplet(error)
    error.message.in?({
      "expecting identifier 'end', not 'EOF'",
      "expecting token 'CONST', not 'EOF'",
      "expecting any of these tokens: IDENT, CONST, `, <<, <, <=, ==, ===, !=, =~, !~, >>, >, >=, +, -, *, /, //, !, ~, %, &, |, ^, **, [], []?, []=, <=>, &+, &-, &*, &** (not 'EOF')",
      "expecting token ')', not 'EOF'",
      "unexpected token: EOF",
      "Unexpected EOF on heredoc identifier",
      "unterminated parenthesized expression",
      "Unterminated string literal", # <= U is upcase ^^
      "unterminated array literal",
      "unterminated macro",
      "unknown token: '\u{0}'",
    })
  end

  def self.run_method(receiver, a_def, args)
    if a_def.args.size != args.size
      raise_error "TODO: default values & named argument"
    end
    hash = {} of String => ICRObject
    a_def.args.each_with_index { |a, i| hash[a.name] = args[i] }

    @@args_context << hash
    @@receiver_context << receiver

    ret = a_def.body.run

    @@args_context.pop
    @@receiver_context.pop
    ret
  end

  def self.run_top_level_method(a_def, args)
    if a_def.args.size != args.size
      raise_error "TODO: default values & named argument"
    end
    hash = {} of String => ICRObject
    a_def.args.each_with_index { |a, i| hash[a.name] = args[i] }
    @@args_context << hash

    ret = a_def.body.run

    @@args_context.pop
    ret
  end

  def self.get_var(name)
    if name == "self"
      return @@receiver_context.last? || raise_error "self into a empty context"
    elsif h = @@args_context.last?
      # args = d.args.select(&.name == name)
      if value = h[name]?
        # puts "found #{name}"
        # i = d.args.index_of(arg[0])
        return value
      else
        raise_error "Cannot found def arg #{name}"
      end
    else
      raise_error "BUG: Context stack is empty"
    end
  end

  def self.assign_var(name, value)
    @@args_context.last[name] = value
  end
end
