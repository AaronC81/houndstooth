require 'parser/ruby30'

# Accuracy to Ruby 3
LEGACY_MODES = %i[lambda procarg0 encoding arg_inside_procarg0 forward_arg kwargs match_pattern]
LEGACY_MODES.each do |mode|
    Parser::Builders::Default.send :"emit_#{mode}=", true
end
Parser::Builders::Default.emit_index = false
Parser::Builders::Default.emit_lambda = false

# Useful resource: https://docs.rs/lib-ruby-parser/3.0.12/lib_ruby_parser/index.html
# Based on whitequark/parser so gives good idea of what node types to expect

module Houndstooth::SemanticNode
    # Shorthand for use by #to_instructions implementations
    I = Houndstooth::Instructions

    class Base
        # @return [Parser::AST::Node]
        attr_accessor :ast_node

        # @return [<Parser::Source::Comment>]
        attr_accessor :comments

        def initialize(ast_node:, **kwargs)
            @comments = []
            @ast_node = ast_node

            kwargs.each do |k, v|
                send :"#{k}=", v
            end
        end

        def self.from_ast(ast_node, **options)
            converter = @@ast_converters[ast_node.type]

            if converter.nil?
                Houndstooth::Errors::Error.new(
                    "Unsupported AST node type #{ast_node.type}",
                    [[ast_node.loc.expression, "unsupported"]]
                ).push
                return
            end

            converter.(ast_node, **options)
        end

        def self.register_ast_converter(*types, &block)
            @@ast_converters ||= {}
            types.each do |type|
                @@ast_converters[type] = block
            end
        end

        # TODO: shouldn't use a global!!
        def self.shift_comments(ast_node)
            # TODO: don't pick *any* comment before this one, only ones on their own line
            # In this case:
            #   x = 2 # foo
            #   y
            # We shouldn't match  the `# foo` comment to the `y` Send

            if ast_node.type == :send && ast_node.location.respond_to?(:selector) && ast_node.location.selector
                # Use name of the method as position reference, if available
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

        # Converts this semantic node into a sequence of equivalent instructions, and adds them to
        # the given instruction block.
        # It is expected that, after this call returns, the variable assigned by the final
        # instruction in the block has an equivalent result to evaluating this expression. 
        # @param [InstructionBlock] block
        def to_instructions(block)
            raise "#to_instructions not implemented for #{self.class.name}"
        end

        protected

        # Extracts type arguments from comments as strings.
        def get_type_arguments
            comments
                .select { |c| c.text.start_with?('#!arg ') }
                .map do |c|
                    unless /^#!arg\s+(.+)\s*$/ === c.text
                        Houndstooth::Errors::Error.new(
                            "Malformed #!arg definition",
                            [[c.loc.expression, "invalid"]]
                        ).push
                        return 
                    end

                    $1
                end
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
require_relative 'semantic_node/super'
