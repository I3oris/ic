abstract class Crystal::SemanticVisitor < Crystal::Visitor
  private def require_file(node : Require, filename : String)
    parser = @program.new_parser(
      File.exists?(filename) ? File.read(filename) : FileStorage.get(filename).gets_to_end
    )
    parser.filename = filename
    parser.wants_doc = @program.wants_doc?
    begin
      parsed_nodes = parser.parse
      parsed_nodes = @program.normalize(parsed_nodes, inside_exp: inside_exp?)
      # We must type the node immediately, in case a file requires another
      # *before* one of the files in `filenames`
      parsed_nodes.accept self
    rescue ex : CodeError
      node.raise "while requiring \"#{node.string}\"", ex
    rescue ex
      raise Error.new "while requiring \"#{node.string}\"", ex
    end

    FileNode.new(parsed_nodes, filename)
  end
end
