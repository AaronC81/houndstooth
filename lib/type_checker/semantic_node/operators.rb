module TypeChecker::SemanticNode
    # A boolean AND operation: `a && b`,
    #
    # Unlike other infix operators, boolean AND and OR are not translated to a `Send`.
    class BooleanAnd < Base
        # @return [SemanticNode]
        attr_accessor :left

        # @return [SemanticNode]
        attr_accessor :right

        register_ast_converter :and do |ast_node|
            left, right = ast_node.to_a.map { from_ast(_1) }

            BooleanAnd.new(ast_node: ast_node, left: left, right: right)
        end 
    end

    # A boolean OR operation: `a || b`,
    #
    # Unlike other infix operators, boolean AND and OR are not translated to a `Send`.
    class BooleanOr < Base
        # @return [SemanticNode]
        attr_accessor :left

        # @return [SemanticNode]
        attr_accessor :right

        register_ast_converter :or do |ast_node|
            left, right = ast_node.to_a.map { from_ast(_1) }

            BooleanOr.new(ast_node: ast_node, left: left, right: right)
        end 
    end

    # A splat: `a = *b` or `[1, 2, *[3, 4], 5]`
    class Splat < Base
        # @return [SemanticNode]
        attr_accessor :value

        # It is possible for splats to appear on the LHS of an assigment, so we need to handle that
        register_ast_converter :splat do |ast_node, multiple_assignment_lhs: false|
            Splat.new(
                ast_node: ast_node,
                value: from_ast(
                    ast_node.to_a.first,
                    multiple_assignment_lhs: multiple_assignment_lhs,
                )
            )
        end
    end

    # A `defined?` check: `defined? x`
    class IsDefined < Base
        # @return [SemanticNode]
        attr_accessor :value

        register_ast_converter :defined? do |ast_node|
            IsDefined.new(ast_node: ast_node, value: from_ast(ast_node.to_a.first))
        end
    end
end

# TODO: and/or-assign
# Desugaring these into an assignment and a boolean operation is tricky for multiple reasons:
#
#   1. We'd have to use a fabricated variable for cases which call a setter method
#      ___fabricated = get_random_class
#      ___fabricated.attribute ||= x
# 
#   2. Class variables are magic!
#      @@y ||= [] is valid
#      @@y = @@y || [] is not
#