module Houndstooth::SemanticNode
    # The `true` keyword.
    class TrueKeyword < Base
        register_ast_converter :true do |ast_node|
            TrueKeyword.new(ast_node: ast_node)
        end
    end

    # The `false` keyword.
    class FalseKeyword < Base
        register_ast_converter :false do |ast_node|
            FalseKeyword.new(ast_node: ast_node)
        end
    end

    # The `self` keyword.
    class SelfKeyword < Base
        register_ast_converter :self do |ast_node|
            SelfKeyword.new(ast_node: ast_node)
        end
    end

    # The `nil` keyword.
    class NilKeyword < Base
        register_ast_converter :nil do |ast_node|
            NilKeyword.new(ast_node: ast_node)
        end
    end
end
