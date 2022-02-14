module Houndstooth; end

require_relative 'houndstooth/errors'
require_relative 'houndstooth/instructions'
require_relative 'houndstooth/semantic_node'
require_relative 'houndstooth/environment'
require_relative 'houndstooth/stdlib'
require_relative 'houndstooth/type_checker'

module Houndstooth
    # Parses a complete file, and adds its type definitions to the given environment.
    # Returns the parsed `SemanticNode`, or if a syntax error occurs, returns `nil`.
    def self.process_file(file_name, file_contents, env)
        # Build parser buffer
        begin
            buffer = Parser::Source::Buffer.new(file_name)
            buffer.source = file_contents
        rescue => e
            Houndstooth::Errors::Error.new("Error building parse buffer: #{e}", []).push
            abort_on_error!
        end
    
        # Parse file into AST nodes
        any_errors = false
        parser = Parser::Ruby30.new

        parser.diagnostics.consumer = ->(diag) do
            any_errors = true
            Houndstooth::Errors::Error.new(
                "Syntax error",
                [[diag.location, diag.message]]
            ).push
        end
        begin
            ast_node, comments = parser.parse_with_comments(buffer)
        rescue Parser::SyntaxError => e
            # We already got a diagnostic for this, don't need to handle it again
        end
        $comments = comments

        return nil if any_errors
        
        # Convert to semantic nodes
        node = Houndstooth::SemanticNode.from_ast(ast_node)

        # Build environment items
        Houndstooth::Environment::Builder.new(node, env).analyze

        node
    end
end
    