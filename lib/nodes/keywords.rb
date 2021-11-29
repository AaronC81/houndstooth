class TrueKeyword < SemanticNode
    register_ast_converter :true do |ast_node|
        TrueKeyword.new(ast_node: ast_node)
    end
end

class FalseKeyword < SemanticNode
    register_ast_converter :false do |ast_node|
        FalseKeyword.new(ast_node: ast_node)
    end
end

class SelfKeyword < SemanticNode
    register_ast_converter :self do |ast_node|
        SelfKeyword.new(ast_node: ast_node)
    end
end

class NilKeyword < SemanticNode
    register_ast_converter :nil do |ast_node|
        NilKeyword.new(ast_node: ast_node)
    end
end
