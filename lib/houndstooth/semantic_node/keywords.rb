module Houndstooth::SemanticNode
    # The `true` keyword.
    class TrueKeyword < Base
        register_ast_converter :true do |ast_node|
            TrueKeyword.new(ast_node: ast_node)
        end

        def to_instructions(block)
            block.instructions << I::LiteralInstruction.new(node: self, value: true)
        end
    end

    # The `false` keyword.
    class FalseKeyword < Base
        register_ast_converter :false do |ast_node|
            FalseKeyword.new(ast_node: ast_node)
        end

        def to_instructions(block)
            block.instructions << I::LiteralInstruction.new(node: self, value: false)
        end
    end

    # The `self` keyword.
    class SelfKeyword < Base
        register_ast_converter :self do |ast_node|
            SelfKeyword.new(ast_node: ast_node)
        end

        def to_instructions(block)
            block.instructions << I::SelfInstruction.new(node: self)
        end
    end

    # The `nil` keyword.
    class NilKeyword < Base
        register_ast_converter :nil do |ast_node|
            NilKeyword.new(ast_node: ast_node)
        end

        def to_instructions(block)
            block.instructions << I::LiteralInstruction.new(node: self, value: nil)
        end
    end
end
