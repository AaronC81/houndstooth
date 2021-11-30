class MethodDefinition < SemanticNode
    # @return [Symbol]
    attr_accessor :name

    # @return [Parameters]
    attr_accessor :parameters

    # @return [SemanticNode, nil]
    attr_accessor :target

    # @return [SemanticNode]
    attr_accessor :body

    register_ast_converter :def do |ast_node|
        name, parameters, body = *ast_node

        body = from_ast(body) if body
        parameters = from_ast(parameters)

        MethodDefinition.new(
            ast_node: ast_node,
            name: name,
            body: body,
            parameters: parameters,
            target: nil,
        )
    end

    register_ast_converter :defs do |ast_node|
        target, name, parameters, body = *ast_node

        target = from_ast(target)
        body = from_ast(body) if body
        parameters = from_ast(parameters)

        MethodDefinition.new(
            ast_node: ast_node,
            name: name,
            body: body,
            parameters: parameters,
            target: target,
        )
    end
end

class ClassDefinition < SemanticNode
    # @return [SemanticNode]
    attr_accessor :name

    # @return [SemanticNode, nil]
    attr_accessor :superclass

    # @return [SemanticNode]
    attr_accessor :body

    register_ast_converter :class do |ast_node|
        name, superclass, body = *ast_node

        name = from_ast(name)
        superclass = from_ast(superclass) if superclass
        body = from_ast(body) if body

        ClassDefinition.new(
            ast_node: ast_node,
            name: name,
            superclass: superclass,
            body: body,
        )
    end
end
