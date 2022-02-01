module Houndstooth::SemanticNode
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

    # Note: It is *probably* possible to desugar the boolean-assign operators.
    #
    # I think `x ||= y` can be translated into:
    #
    #   if !(defined?(x) && x)
    #     x = y
    #   end
    #   
    # If the source of `x` is not idempotent, this is not _strictly_ correct - if our `x`
    # was `do_something_random.x`, then we'd call `do_something_random` twice rather than
    # once. But it might be close enough for static analysis purposes?

    # An assignment using a boolean AND operator: `x &&= 3`
    #
    # This is NOT equivalent to `x = x && 3`.
    class BooleanAndAssignment < Base
        # @return [SemanticNode]
        attr_accessor :target

        # @return [SemanticNode]
        attr_accessor :value

        register_ast_converter :and_asgn do |ast_node|
            target, value = *ast_node

            # It's not *really* a multiple assignment LHS, but it's the easiest way to get e.g. a
            # LocalVariable from (lvasgn :x), so we'll just pretend
            target = from_ast(target, multiple_assignment_lhs: true)
            value = from_ast(value)

            BooleanAndAssignment.new(
                ast_node: ast_node,
                target: target,
                value: value,
            )
        end
    end

    # An assignment using a boolean OR operator: `x ||= 3`
    #
    # This is NOT equivalent to `x = x || 3`.
    class BooleanOrAssignment < Base
        # @return [SemanticNode]
        attr_accessor :target

        # @return [SemanticNode]
        attr_accessor :value

        register_ast_converter :or_asgn do |ast_node|
            target, value = *ast_node

            # It's not *really* a multiple assignment LHS, but it's the easiest way to get e.g. a
            # LocalVariable from (lvasgn :x), so we'll just pretend
            target = from_ast(target, multiple_assignment_lhs: true)
            value = from_ast(value)

            BooleanOrAssignment.new(
                ast_node: ast_node,
                target: target,
                value: value,
            )
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
