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

        root_conditional
    end
end
