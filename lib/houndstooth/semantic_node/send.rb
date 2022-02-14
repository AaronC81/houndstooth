module Houndstooth::SemanticNode
    # A method call, called a 'send' internally by Ruby and its parser, hence its name here.
    class Send < Base
        # @return [SemanticNode, nil]
        attr_accessor :target
        
        # @return [Symbol]
        attr_accessor :method

        # @return [<SemanticNode>]
        attr_accessor :arguments

        # @return [Boolean]
        attr_accessor :safe_navigation

        # If true, this isn't really a send, but instead a super call. The `target` and `method` 
        # of this instance should be ignored.
        # @return [Boolean]
        attr_accessor :super_call

        # @return [Block, nil]
        attr_accessor :block

        register_ast_converter :send do |ast_node, multiple_assignment_lhs: false|
            target, method, *arguments_nodes = *ast_node
            
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
                    arguments: [PositionalArgument.new(MagicPlaceholder.new)],
                    safe_navigation: false,
                )
            end 

            if arguments_nodes.last&.type == :kwargs
                arguments = arguments_nodes[0...-1].map { PositionalArgument.new(from_ast(_1)) }
                arguments.concat(arguments_nodes.last.to_a.map do |kwarg|
                    next [:_, nil] if kwarg.type == :kwsplat

                    unless kwarg.type == :pair
                        Houndstooth::Errors::Error.new(
                            "Expected keyword argument list to contain only pairs",
                            [[kwarg.loc.expression, "did not parse as a pair"]]
                        ).push
                        next nil
                    end

                    name, value = *kwarg.to_a.map { from_ast(_1) }
                    KeywordArgument.new(value, name: name)
                end)
            else
                arguments = arguments_nodes.map { PositionalArgument.new(from_ast(_1)) }
            end

            Send.new(
                ast_node: ast_node,
                comments: comments,

                target: target,
                method: method,
                arguments: arguments,
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
                body: block_body.nil? ? Body.new(ast_node: ast_node) : from_ast(block_body)
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

        def to_instructions(block)
            # Generate instructions for the method's target
            # If it doesn't have one, then it's implicitly `self`
            if target
                target.to_instructions(block)
            else
                block.instructions << I::SelfInstruction.new(block: block, node: self)
            end
            target_variable = block.instructions.last.result

            # If this call uses save navigation, we want to wrap everything else in a conditional
            # which checks the target isn't nil
            # (If safe navigation bails from a call because the target is nil, the arguments don't
            #  get evaluated either)
            if safe_navigation
                # Generates:
                #   $1 = ...target...
                #   if $2.nil?
                #     nil
                #   else
                #     $1.method
                #   end
                block.instructions << I::SendInstruction.new(
                    block: block,
                    node: self,
                    target: target_variable,
                    method_name: :nil?,
                )

                true_blk = I::InstructionBlock.new(has_scope: false, parent: block)
                true_blk.instructions << I::LiteralInstruction.new(block: true_blk, node: self, value: nil)
                block.instructions << I::ConditionalInstruction.new(
                    block: block,
                    node: self,
                    condition: block.instructions.last.result,
                    true_branch: true_blk,
                    false_branch: I::InstructionBlock.new(has_scope: false, parent: block),
                )

                # Replace the working instruction block with the false branch, so we insert the
                # actual send in there
                block = block.instructions.last.false_branch
            end

            # Evaluate arguments
            ins_args = arguments.map do |arg|
                case arg
                when PositionalArgument
                    arg.node.to_instructions(block)
                    I::PositionalArgument.new(block.instructions.last.result)
                when KeywordArgument
                    if arg.name.is_a?(SymbolLiteral) && arg.name.components.length == 1 && arg.name.components.first.is_a?(String)
                        arg.node.to_instructions(block)
                        I::KeywordArgument.new(
                            block.instructions.last.result,
                            name: arg.name.components.first,
                        )
                    else
                        Houndstooth::Errors::Error.new(
                            "Keyword argument keys must be non-interpolated symbol literals",
                            [[arg.name.ast_node.loc.expression, "invalid key"]]
                        ).push
    
                        block.instructions << I::LiteralInstruction.new(block: block, node: arg.name, value: nil)
                        I::KeywordArgument.new(
                            block.instructions.last.result,
                            name: "__non_symbol_key_error_#{(rand * 10000).to_i}",
                        )
                    end
                else
                    raise "unknown node argument type: #{arg}"
                end
            end
            
            # Insert send instruction
            si = I::SendInstruction.new(
                block: block,
                node: self,
                target: target_variable,
                method_name: method,
                arguments: ins_args,
                super_call: super_call,
            )

            # Build up method block
            if self.block
                si.method_block =
                    I::InstructionBlock.new(has_scope: true, parent: si).tap do |blk|
                        params = self.block.parameters

                        if params.optional_parameters.any? ||
                            params.keyword_parameters.any? ||
                            params.optional_keyword_parameters.any? ||
                            params.rest_parameter ||
                            params.rest_keyword_parameter ||
                            params.has_forward_parameter ||
                            params.block_parameter ||
                            params.only_proc_parameter

                            # Replace call with a nil
                            Houndstooth::Errors::Error.new(
                                "Only required positional parameters are supported",
                                [[ast_node.loc.expression, "unsupported parameters in block"]]
                            ).push 
                            blk.instructions << I::LiteralInstruction.new(node: self, block: blk, value: nil)
                            return
                        end

                        # Create parameters on this block
                        params.positional_parameters.each do |name|
                            blk.parameters << I::Variable.new(name.to_s)
                        end

                        # Create body
                        self.block.body.to_instructions(blk)
                    end
            end

            block.instructions << si
        end
    end

    # A block passed to a `Send`.
    class Block < Base
        # @return [Parameters]
        attr_accessor :parameters

        # @return [SemanticNode]
        attr_accessor :body
    end

    # An argument to a `Send`.
    # @abstract
    class Argument
        # The node for the argument's value.
        # @return [SemanticNode]
        attr_accessor :node

        def initialize(node)
            @node = node
        end
    end

    # A standard, singular, positional argument.
    class PositionalArgument < Argument; end

    # A singular keyword argument.
    class KeywordArgument < Argument
        # The keyword.
        # @return [SemanticNode]
        attr_accessor :name

        def initialize(node, name:)
            super(node)
            @name = name
        end
    end 

    # A special argument which may appear in the arguments to a `Send`, when arguments have been
    # forwarded from the enclosing method into it.
    class ForwardedArguments < Base
        register_ast_converter :forwarded_args do |ast_node|
            ForwardedArguments.new(ast_node: ast_node)
        end
    end
end
