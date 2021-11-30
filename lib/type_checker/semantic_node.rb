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

        def initialize(**kwargs)
            kwargs.each do |k, v|
                send :"#{k}=", v
            end
        end

        # TODO: this may need to be able to produce more than one node
        # e.g:
        #   case x
        #   when y
        #     ...
        #   end
        # Needs to become:
        #   ___temp_1 = x
        #   if y === ___temp_1
        #     ...
        #   end
        def self.from_ast(ast_node)
            converter = @@ast_converters[ast_node.type]
            raise "unsupported AST node type: #{ast_node}" if converter.nil?

            converter.(ast_node)
        end

        def self.register_ast_converter(type, &block)
            @@ast_converters ||= {}
            @@ast_converters[type] = block
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
