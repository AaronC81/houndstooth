require_relative 'type_checker'

def code_to_semantic_node(code)
    buffer = Parser::Source::Buffer.new("arg")
    buffer.source = code

    ast_node, comments = Parser::Ruby30.new.parse_with_comments(buffer)
    $comments = comments
    TypeChecker::SemanticNode.from_ast(ast_node)
end

if __FILE__ == $0
    node = code_to_semantic_node(File.read(ARGV[0]))
    env = TypeChecker::Environment.new
    TypeChecker::Stdlib.add_types(env)
    TypeChecker::Environment::Builder.new(node, env).analyze

    if TypeChecker::Errors.errors.any?
        TypeChecker::Errors.errors.each do |error|
            puts error.format
            puts
        end
    else
        puts "All done!"
        puts "Types:"
        puts env.types.keys.map { |name| "  - #{name}"}
    end
end
