require_relative 'houndstooth'

def code_to_semantic_node(code)
    buffer = Parser::Source::Buffer.new("arg")
    buffer.source = code

    ast_node, comments = Parser::Ruby30.new.parse_with_comments(buffer)
    $comments = comments
    Houndstooth::SemanticNode.from_ast(ast_node)
end

if __FILE__ == $0
    env = Houndstooth::Environment.new
    Houndstooth::Stdlib.add_types(env)

    if ARGV[0] == "--assembly"
        node = code_to_semantic_node(ARGV[1])
        block = Houndstooth::Instructions::InstructionBlock.new(has_scope: true, parent: nil)
        node.to_instructions(block)

        checker = Houndstooth::TypeChecker.new(env)
        checker.process_block(block)

        if Houndstooth::Errors.errors.any?
            Houndstooth::Errors.errors.each do |error|
                puts error.format
                puts
            end
        else
            puts block.to_assembly
        end
    else
        node = code_to_semantic_node(File.read(ARGV[0]))
        Houndstooth::Environment::Builder.new(node, env).analyze

        if Houndstooth::Errors.errors.any?
            Houndstooth::Errors.errors.each do |error|
                puts error.format
                puts
            end
        else
            puts "All done!"
            puts "Types:"
            puts env.types.keys.map { |name| "  - #{name}"}
        end
    end
end
