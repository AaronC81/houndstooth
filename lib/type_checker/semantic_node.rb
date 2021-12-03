require 'parser/ruby30'

# Accuracy to Ruby 3
LEGACY_MODES = %i[lambda procarg0 encoding arg_inside_procarg0 forward_arg kwargs match_pattern]
LEGACY_MODES.each do |mode|
    Parser::Builders::Default.send :"emit_#{mode}=", true
end
Parser::Builders::Default.emit_index = false

# Useful resource: https://docs.rs/lib-ruby-parser/3.0.12/lib_ruby_parser/index.html
# Based on whitequark/parser so gives good idea of what node types to expect

module TypeChecker::SemanticNode
    class Base
        # @return [Parser::AST::Node]
        attr_accessor :ast_node

        # @return [<Parser::Source::Comment>]
        attr_accessor :comments

        def initialize(**kwargs)
            @comments = []

            kwargs.each do |k, v|
                send :"#{k}=", v
            end
        end

        def self.from_ast(ast_node, **options)
            converter = @@ast_converters[ast_node.type]
            raise "unsupported AST node type: #{ast_node}" if converter.nil?

            converter.(ast_node, **options)
        end

        def self.register_ast_converter(type, &block)
            @@ast_converters ||= {}
            @@ast_converters[type] = block
        end

        # TODO: shouldn't use a global!!
        def self.shift_comments(ast_node)
            # TODO: don't pick *any* comment before this one, only ones on their own line
            # In this case:
            #   x = 2 # foo
            #   y
            # We shouldn't match  the `# foo` comment to the `y` Send

            if ast_node.type == :send
                # Use name of the method as position reference
                reference_location = ast_node.location.selector
            else
                # Not sure what this is, just use the very start of the expression
                reference_location = ast_node.location.expression
            end

            comments = []
            comments << $comments.shift \
                while $comments.first && $comments.first.location.expression < reference_location
            comments
        end
    end

    def self.from_ast(...)
        Base.from_ast(...)
    end
end

require_relative 'semantic_node/parameters'
require_relative 'semantic_node/control_flow'
require_relative 'semantic_node/operators'
require_relative 'semantic_node/identifiers'
require_relative 'semantic_node/keywords'
require_relative 'semantic_node/literals'
require_relative 'semantic_node/send'
require_relative 'semantic_node/definitions'
