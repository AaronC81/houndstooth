module Houndstooth; end

require_relative 'houndstooth/errors'
require_relative 'houndstooth/instructions'
require_relative 'houndstooth/semantic_node'
require_relative 'houndstooth/environment'
require_relative 'houndstooth/stdlib'
require_relative 'houndstooth/type_checker'

module Houndstooth
    # Parses a complete file, and adds its type definitions to the given environment.
    # Returns the parsed `SemanticNode`.
    def self.process_file(file_name, file_contents, env)
        # Build parser buffer
        buffer = Parser::Source::Buffer.new(file_name)
        buffer.source = file_contents
    
        # Parse file into AST nodes
        ast_node, comments = Parser::Ruby30.new.parse_with_comments(buffer)
        $comments = comments
        
        # Convert to semantic nodes
        node = Houndstooth::SemanticNode.from_ast(ast_node)

        # Build environment items
        Houndstooth::Environment::Builder.new(node, env).analyze

        node
    end
end
    