# Useful resource: https://docs.rs/lib-ruby-parser/3.0.12/lib_ruby_parser/index.html
# Based on whitequark/parser so gives good idea of what node types to expect

Location = Struct.new('Location', :file, :line, :col)

class SemanticNode
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

class TrueKeyword < SemanticNode
    register_ast_converter :true do |ast_node|
        TrueKeyword.new(ast_node: ast_node)
    end
end

class FalseKeyword < SemanticNode
    register_ast_converter :false do |ast_node|
        FalseKeyword.new(ast_node: ast_node)
    end
end

class SelfKeyword < SemanticNode
    register_ast_converter :self do |ast_node|
        SelfKeyword.new(ast_node: ast_node)
    end
end

class NilKeyword < SemanticNode
    register_ast_converter :nil do |ast_node|
        NilKeyword.new(ast_node: ast_node)
    end
end

class Constant < SemanticNode
    # @return [SemanticNode, nil]
    attr_accessor :target

    # @return [Symbol]
    attr_accessor :name

    register_ast_converter :const do |ast_node|
        target, name = *ast_node
        target = from_ast(target) if target

        Constant.new(
            ast_node: ast_node,
            target: target,
            name: name,
        )
    end
end

class ConstantBase < SemanticNode
    register_ast_converter :cbase do |ast_node|
        ConstantBase.new(ast_node: ast_node)
    end 
end

class Body < SemanticNode
    # @return [<SemanticNode>]
    attr_accessor :nodes

    register_ast_converter :begin do |ast_node|
        if ast_node.to_a.length == 1
            from_ast(ast_node.to_a.first)
        else
            Body.new(
                ast_node: ast_node,
                nodes: ast_node.to_a.map { from_ast(_1) }
            )
        end
    end
end

class Send < SemanticNode
    # @return [SemanticNode, nil]
    attr_accessor :target
    
    # @return [Symbol]
    attr_accessor :method

    # @return [<SemanticNode>]
    attr_accessor :positional_arguments

    # @return [{SemanticNode => SemanticNode}]
    attr_accessor :keyword_arguments

    # @return [Block, nil]
    attr_accessor :block

    register_ast_converter :send do |ast_node|
        target, method, *arguments = *ast_node
        target = from_ast(target) if target

        if arguments.last&.type == :kwargs
            positional_arguments = arguments[0...-1].map { from_ast(_1) }
            keyword_arguments = arguments.last.to_a.to_h do |kwarg|
                raise unless kwarg.type == :pair
                kwarg.to_a.map { from_ast(_1) }
            end
        else
            positional_arguments = arguments.map { from_ast(_1) }
            keyword_arguments = []
        end

        Send.new(
            ast_node: ast_node,
            target: target,
            method: method,
            positional_arguments: positional_arguments,
            keyword_arguments: keyword_arguments,
        )
    end

    register_ast_converter :block do |ast_node|
        send_ast_node, args_ast_node, block_body = *ast_node

        # Parse the `send`, we'll set block properties afterwards
        send = from_ast(send_ast_node)
        send.ast_node = ast_node


        # TODO: support "procarg0" form
        # TODO: support numbered arguments

        send.block = Block.new(
            positional_parameters: [],
            optional_parameters: [],
            keyword_parameters: [],
            optional_keyword_parameters: [],
            rest_parameter: nil,
            rest_keyword_parameter: nil,
        )
        args_ast_node.to_a.each do |arg|
            case arg.type
            when :arg
                send.block.positional_parameters << arg.to_a.first
            when :kwarg
                send.block.keyword_parameters << arg.to_a.first
            when :optarg
                name, value = *arg
                send.block.optional_parameters << [name, from_ast(value)]
            when :kwoptarg
                name, value = *arg
                send.block.optional_keyword_parameters << [name, from_ast(value)]
            when :restarg
                send.block.rest_parameter = arg.to_a.first
            when :kwrestarg
                send.block.rest_keyword_parameter = arg.to_a.first 
            else
                raise "unsupported argument type: #{arg}"
            end
        end

        send.block.body = from_ast(block_body)

        send
    end
end

class Block < SemanticNode
    # @return [<Symbol>]
    attr_accessor :positional_parameters
    
    # @return [<(Symbol, SemanticNode)>]
    attr_accessor :optional_parameters
    
    # @return [<Symbol>]
    attr_accessor :keyword_parameters
    
    # @return [<(Symbol, SemanticNode)>]
    attr_accessor :optional_keyword_parameters

    # @return [Symbol, nil]
    attr_accessor :rest_parameter

    # @return [Symbol, nil]
    attr_accessor :rest_keyword_parameter

    # @return [SemanticNode]
    attr_accessor :body
end

class IntegerLiteral < SemanticNode
    # @return [Integer]
    attr_accessor :value

    register_ast_converter :int do |ast_node|
        IntegerLiteral.new(ast_node: ast_node, value: ast_node.to_a.first)
    end
end

class StringLiteral < SemanticNode
    # @return [<String, SemanticNode>]
    attr_accessor :components

    register_ast_converter :str do |ast_node|
        StringLiteral.new(ast_node: ast_node, components: [ast_node.to_a.first])
    end

    register_ast_converter :dstr do |ast_node|
        components = ast_node.to_a.map do |part|
            if part.type == :str
                part.to_a.first
            else
                from_ast(part)
            end
        end

        StringLiteral.new(ast_node: ast_node, components: components)
    end
end

class SymbolLiteral < SemanticNode
    # @return [<String, SemanticNode>]
    attr_accessor :components

    register_ast_converter :sym do |ast_node|
        SymbolLiteral.new(ast_node: ast_node, components: [ast_node.to_a.first.to_s])
    end

    register_ast_converter :dsym do |ast_node|
        components = ast_node.to_a.map do |part|
            if part.type == :str
                part.to_a.first.to_s
            else
                from_ast(part)
            end
        end

        SymbolLiteral.new(ast_node: ast_node, components: components)
    end
end

class LocalVariable < SemanticNode
    # @return [Symbol]
    attr_accessor :name

    register_ast_converter :lvar do |ast_node|
        LocalVariable.new(ast_node: ast_node, name: ast_node.to_a.first)
    end
end

class LocalVariableAssignment < SemanticNode
    # @return [Symbol]
    attr_accessor :name

    # @return [SemanticNode]
    attr_accessor :value

    register_ast_converter :lvasgn do |ast_node|
        name, value = *ast_node
        value = from_ast(value)
        
        LocalVariableAssignment.new(
            ast_node: ast_node,
            name: name,
            value: value,
        )
    end
end

class Conditional < SemanticNode
    # @return [SemanticNode]
    attr_accessor :condition

    # @return [SemanticNode]
    attr_accessor :true_branch

    # @return [SemanticNode, nil]
    attr_accessor :false_branch

    register_ast_converter :if do |ast_node|
        condition, true_branch, false_branch = ast_node.to_a.map { from_ast(_1) if _1 }

        Conditional.new(
            condition: condition,
            true_branch: true_branch,
            false_branch: false_branch,
        )
    end
end

# -------

require 'parser/ruby30'

# Accuracy to Ruby 3
LEGACY_MODES = %i[lambda procarg0 encoding index arg_inside_procarg0 forward_arg kwargs match_pattern]
LEGACY_MODES.each do |mode|
    Parser::Builders::Default.send :"emit_#{mode}=", true
end

def code_to_semantic_node(code)
    buffer = Parser::Source::Buffer.new("arg")
    buffer.source = code

    ast_node = Parser::Ruby30.new.parse(buffer)
    SemanticNode.from_ast(ast_node)
end

pp code_to_semantic_node(ARGV[0]) if __FILE__ == $0
