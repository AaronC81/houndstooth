require_relative 'nodes'

def code_to_semantic_node(code)
    buffer = Parser::Source::Buffer.new("arg")
    buffer.source = code

    ast_node = Parser::Ruby30.new.parse(buffer)
    SemanticNode.from_ast(ast_node)
end

pp code_to_semantic_node(ARGV[0]) if __FILE__ == $0
