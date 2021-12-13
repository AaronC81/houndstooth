module TypeChecker::SemanticNode
    # An implicit super call, without parentheses. This will forward arguments to the superclass'
    # method automatically.
    class ImplicitSuper < Base
        register_ast_converter :zsuper do |ast_node|
            self.new(ast_node: ast_node)
        end
    end

    # ...Where's `ExplicitSuper`?
    # We use `Send` for that, since the parameters are largely the same!
end
