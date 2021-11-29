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
            parameters: Parameters.new,
        )
        args_ast_node.to_a.each do |arg|
            case arg.type
            when :arg
                send.block.parameters.positional_parameters << arg.to_a.first
            when :kwarg
                send.block.parameters.keyword_parameters << arg.to_a.first
            when :optarg
                name, value = *arg
                send.block.parameters.optional_parameters << [name, from_ast(value)]
            when :kwoptarg
                name, value = *arg
                send.block.parameters.optional_keyword_parameters << [name, from_ast(value)]
            when :restarg
                send.block.parameters.rest_parameter = arg.to_a.first
            when :kwrestarg
                send.block.parameters.rest_keyword_parameter = arg.to_a.first 
            else
                raise "unsupported argument type: #{arg}"
            end
        end

        send.block.body = from_ast(block_body)

        send
    end
end

class Block < SemanticNode
    # @return [Parameters]
    attr_accessor :parameters

    # @return [SemanticNode]
    attr_accessor :body
end
