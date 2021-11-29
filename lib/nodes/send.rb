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
