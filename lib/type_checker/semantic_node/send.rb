module TypeChecker::SemanticNode
    # A method call, called a 'send' internally by Ruby and its parser, hence its name here.
    class Send < Base
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
            
            # Let the target shift comments first!
            # This is because you can break onto newlines on the dots if you need to apply a comment
            # to another node.
            #
            # Say you need to apply a magic comment to all of the three sends in a chain:
            #
            #    a.b.c
            #
            # Appying to the first send in the chain (the "deepest target") allows you to do this:
            #
            #    # Comment A
            #    a
            #      # Comment B
            #      .b
            #      # Comment C
            #      .c
            #
            # Rather than what you've have to do if they apply to the end of the chain:
            #
            #    # Comment A
            #    _a = a
            #    # Comment B
            #    _b = a.b
            #    # Comment C
            #    _c = b.c
            #
            target = from_ast(target) if target
            comments = shift_comments(ast_node)

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
                comments: comments,

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
                parameters: from_ast(args_ast_node),
                body: from_ast(block_body)
            )

            send
        end
    end

    # A block passed to a `Send`.
    class Block < Base
        # @return [Parameters]
        attr_accessor :parameters

        # @return [SemanticNode]
        attr_accessor :body
    end
end
