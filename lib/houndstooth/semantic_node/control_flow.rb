module Houndstooth::SemanticNode
    # Used to group a sequence of nodes into one node - for example, when the body of a method
    # definition contains more than one statement.
    #
    # In an ideal world, this class wouldn't exist, and instead we'd use an array everywhere it's
    # possible for multiple nodes to exist. However, it turns out bodies are valid virtually
    # everywhere! The following are valid snippets of Ruby code...
    #
    #   - 1 + (x = 2; x * x)
    #   - something((a; b; c), (d; e; f))
    #   - class (s = :IO; Object.const_get(s))::Something; end
    class Body < Base
        # @return [<SemanticNode>]
        attr_accessor :nodes

        register_ast_converter :begin do |ast_node|
            if ast_node.to_a.length == 1
                from_ast(ast_node.to_a.first)
            else
                Body.new(
                    ast_node: ast_node,

                    # Use a flat map so that we can flatten inner Body nodes into this one
                    nodes: ast_node.to_a.flat_map do |ast_node|
                        sem_node = from_ast(ast_node)
                        if sem_node.is_a?(Body)
                            sem_node.nodes
                        else
                            [sem_node]
                        end
                    end
                )
            end
        end

        def to_instructions(block)
            # A body could signify a new scope, but not always, so we'll let the upper node in the
            # tree create one if needed
            nodes.each do |node|
                node.to_instructions(block)
            end
        end
    end

    # A conditional with true and false branches, used to represent `if` statements, ternary
    # conditionals, and `case/when` constructs.
    class Conditional < Base
        # @return [SemanticNode]
        attr_accessor :condition

        # @return [SemanticNode]
        attr_accessor :true_branch

        # @return [SemanticNode, nil]
        attr_accessor :false_branch

        register_ast_converter :if do |ast_node|
            condition, true_branch, false_branch = ast_node.to_a.map { from_ast(_1) if _1 }

            Conditional.new(
                ast_node: ast_node,
                condition: condition,
                true_branch: true_branch,
                false_branch: false_branch,
            )
        end

        register_ast_converter :case do |ast_node|
            subject, *ast_whens, else_case = *ast_node

            subject = from_ast(subject)
            whens = ast_whens.map { |w| w.to_a.map { from_ast(_1) if _1 } } # [[value, body], ...]
            else_case = from_ast(else_case) if else_case

            # Convert into assignment and conditional chain
            fabricated_subject_var = LocalVariable.fabricate
            fabricated_subject_var_asgn = VariableAssignment.new(
                ast_node: nil,
                target: fabricated_subject_var,
                value: subject,
            )

            # Add each `when` as the false branch of the previous one
            root_conditional = nil
            last_conditional = nil

            whens.each.with_index do |_when, i|
                value, body = *_when

                this_conditional = Conditional.new(
                    ast_node: ast_whens[i],

                    # `when x` is equivalent to `x === subject`
                    condition: Send.new(
                        ast_node: ast_whens[i],

                        target: value,
                        method: :===,
                        positional_arguments: [fabricated_subject_var],
                    ),
                    true_branch: body,
                    false_branch: nil,
                )

                if last_conditional
                    last_conditional.false_branch = this_conditional
                    last_conditional = this_conditional
                else
                    root_conditional = this_conditional
                    last_conditional = this_conditional
                end
            end

            # It is syntactically enforced that a `case` will have at least one `when`, so this is safe
            last_conditional.false_branch = else_case

            Body.new(
                ast_node: ast_node,
                nodes: [
                    fabricated_subject_var_asgn,
                    root_conditional,
                ]
            )
        end

        def to_instructions(block)
            condition.to_instructions(block)
            block.instructions << I::ConditionalInstruction.new(
                block: block,
                node: self,
                condition: block.instructions.last.result,
                true_branch:
                    I::InstructionBlock.new(has_scope: false, parent: block).tap do |blk|
                        true_branch.to_instructions(blk)
                    end,
                false_branch:
                    I::InstructionBlock.new(has_scope: false, parent: block).tap do |blk|
                        if false_branch.nil?
                            blk.instructions << I::LiteralInstruction.new(block: blk, node: self, value: nil)
                        else
                            false_branch.to_instructions(blk)
                        end
                    end,
            )
        end
    end

    # A while loop.
    #
    # TODO: It's possible this can be desugared into Kernel.loop { break unless condition; body }
    class While < Base
        # @return [SemanticNode]
        attr_accessor :condition

        # @return [SemanticNode]
        attr_accessor :body

        register_ast_converter :while do |ast_node|
            condition, body = ast_node.to_a.map { from_ast(_1) if _1 }

            While.new(
                ast_node: ast_node,
                condition: condition,
                body: body,
            )
        end
    end

    # A mixin for defining expressions which affect the control of their enclosing contexts, e.g.
    # `return` and `break`. These all take one optional arguments, so we can deduplicate their
    # definitions.
    module ControlExpressionMixin
        def control_exp_mixin(type)
            # @return [SemanticNode, nil]
            attr_accessor :value
            
            register_ast_converter type do |ast_node|
                if ast_node.to_a.length > 1
                    value = ArrayLiteral.new(
                        ast_node: ast_node,
                        nodes: ast_node.to_a.map { from_ast(_1) },
                    )
                else
                    value = ast_node.to_a.first
                    value = from_ast(value) if value
                end

                self.new(ast_node: ast_node, value: value)
            end
        end
    end

    # A return expression.
    class Return < Base
        extend ControlExpressionMixin
        control_exp_mixin :return
    end

    # A break expression.
    class Break < Base
        extend ControlExpressionMixin
        control_exp_mixin :break
    end

    # A next expression.
    class Next < Base
        extend ControlExpressionMixin
        control_exp_mixin :next
    end
end
