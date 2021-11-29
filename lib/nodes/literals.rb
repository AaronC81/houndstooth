class IntegerLiteral < SemanticNode
    # @return [Integer]
    attr_accessor :value

    register_ast_converter :int do |ast_node|
        IntegerLiteral.new(ast_node: ast_node, value: ast_node.to_a.first)
    end
end

class FloatLiteral < SemanticNode
    # @return [Float]
    attr_accessor :value

    register_ast_converter :float do |ast_node|
        FloatLiteral.new(ast_node: ast_node, value: ast_node.to_a.first)
    end
end

class StringLiteral < SemanticNode
    # @return [<String, SemanticNode>]
    attr_accessor :components

    register_ast_converter :str do |ast_node|
        StringLiteral.new(ast_node: ast_node, components: [ast_node.to_a.first])
    end

    register_ast_converter :dstr do |ast_node|
        components = ast_node.to_a.map do |part|
            if part.type == :str
                part.to_a.first
            else
                from_ast(part)
            end
        end

        StringLiteral.new(ast_node: ast_node, components: components)
    end
end

class SymbolLiteral < SemanticNode
    # @return [<String, SemanticNode>]
    attr_accessor :components

    register_ast_converter :sym do |ast_node|
        SymbolLiteral.new(ast_node: ast_node, components: [ast_node.to_a.first.to_s])
    end

    register_ast_converter :dsym do |ast_node|
        components = ast_node.to_a.map do |part|
            if part.type == :str
                part.to_a.first.to_s
            else
                from_ast(part)
            end
        end

        SymbolLiteral.new(ast_node: ast_node, components: components)
    end
end

class ArrayLiteral < SemanticNode
    # @return [<SemanticNode>]
    attr_accessor :nodes

    register_ast_converter :array do |ast_node|
        ArrayLiteral.new(
            ast_node: ast_node,
            nodes: ast_node.to_a.map { |node| from_ast(node) }
        )
    end
end

class HashLiteral < SemanticNode
    # @return [<(SemanticNode, SemanticNode)>]
    attr_accessor :pairs

    register_ast_converter :hash do |ast_node|
        HashLiteral.new(
            ast_node: ast_node,
            pairs: ast_node.to_a.map { |pair| pair.to_a.map { from_ast(_1) } }
        )
    end
end
