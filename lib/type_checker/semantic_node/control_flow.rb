module TypeChecker::SemanticNode
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
                condition: condition,
                true_branch: true_branch,
                false_branch: false_branch,
            )
        end

        register_ast_converter :case do |ast_node|
            subject, *whens, else_case = *ast_node

            subject = from_ast(subject)
            whens = whens.map { |w| w.to_a.map { from_ast(_1) } } # [[value, body], ...]
            else_case = from_ast(else_case) if else_case

            # Convert into assignment and conditional chain
            fabricated_subject_var = LocalVariable.fabricate
            fabricated_subject_var_asgn = LocalVariableAssignment.new(
                ast_node: nil,
                name: fabricated_subject_var.name,
                value: subject,
            )

            # Add each `when` as the false branch of the previous one
            root_conditional = nil
            last_conditional = nil

            whens.each do |(value, body)|
                this_conditional = Conditional.new(
                    # `when x` is equivalent to `x === subject`
                    condition: Send.new(
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
    end
end
