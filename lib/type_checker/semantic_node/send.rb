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

        # @return [Boolean]
        attr_accessor :safe_navigation

        # If true, this isn't really a send, but instead a super call. The `target` and `method` 
        # of this instance should be ignored.
        # @return [Boolean]
        attr_accessor :super_call

        # @return [Block, nil]
        attr_accessor :block

        register_ast_converter :send do |ast_node, multiple_assignment_lhs: false|
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

            if multiple_assignment_lhs
                next Send.new(
                    ast_node: ast_node,
                    comments: comments,

                    target: target,
                    method: method,
                    positional_arguments: [MagicPlaceholder.new],
                    keyword_arguments: [],
                    safe_navigation: false,
                )
            end 

            if arguments.last&.type == :kwargs
                positional_arguments = arguments[0...-1].map { from_ast(_1) }
                keyword_arguments = arguments.last.to_a.to_h do |kwarg|
                    next [:_, nil] if kwarg.type == :kwsplat

                    unless kwarg.type == :pair
                        TypeChecker::Errors::Error.new(
                            "Expected keyword argument list to contain only pairs",
                            [[kwarg.loc.expression, "did not parse as a pair"]]
                        ).push
                        next nil
                    end

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
                safe_navigation: false,
            )
        end

        register_ast_converter :csend do |ast_node, multiple_assignment_lhs: false|
            # Convert this csend into a send
            equivalent_send_node = Parser::AST::Node.new(:send, ast_node, location: ast_node.location)

            # Convert that into a semantic node and set the safe flag
            send = from_ast(equivalent_send_node, multiple_assignment_lhs: multiple_assignment_lhs)
            send.safe_navigation = true

            send
        end

        register_ast_converter :block do |ast_node|
            send_ast_node, args_ast_node, block_body = *ast_node

            # Parse the `send`, we'll set block properties afterwards
            send = from_ast(send_ast_node)
            send.ast_node = ast_node

            send.block = Block.new(
                ast_node: ast_node,
                parameters: from_ast(args_ast_node),
                body: from_ast(block_body)
            )

            send
        end

        # Numblocks are just converted into regular blocks with the same parameter names, e.g.:
        #
        #   array.map { _1 + 1 }
        #
        # Becomes:
        #
        #   array.map { |_1| _1 + 1 }
        #
        register_ast_converter :numblock do |ast_node|
            send_ast_node, args_count, block_body = *ast_node

            # Parse the `send`, we'll set block properties afterwards
            send = from_ast(send_ast_node)
            send.ast_node = ast_node

            # Build a fake set of parameters for the block
            # We need to respect the "procarg0" semantics by checking if there's only 1 parameter
            if args_count == 1
                parameters = Parameters.new(
                    ast_node: block_body,
                    positional_parameters: [],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                    rest_parameter: nil,
                    rest_keyword_parameter: nil,
                    only_proc_parameter: true,
                )
            else
                parameters = Parameters.new(
                    ast_node: block_body,
                    positional_parameters: args_count.times.map { |i| :"_#{i + 1}" },
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                    rest_parameter: nil,
                    rest_keyword_parameter: nil,
                    only_proc_parameter: false,
                )
            end

            send.block = Block.new(
                ast_node: ast_node,
                parameters: parameters,
                body: from_ast(block_body)
            )

            send
        end

        # Supers are virtually identical to method calls in terms of the arguments they can take.
        register_ast_converter :super do |ast_node|
            # Convert this super into a fake send node
            equivalent_send_node = Parser::AST::Node.new(
                :send,
                [
                    # Target
                    nil,

                    # Method
                    :super__NOT_A_REAL_METHOD,

                    # Arguments
                    *ast_node
                ],
                location: ast_node.location
            )

            # Convert that into a semantic node and set the super flag
            send = from_ast(equivalent_send_node)
            send.super_call = true

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

    # A special argument which may appear in the arguments to a `Send`, when arguments have been
    # forwarded from the enclosing method into it.
    class ForwardedArguments < Base
        register_ast_converter :forwarded_args do |ast_node|
            ForwardedArguments.new(ast_node: ast_node)
        end
    end
end
