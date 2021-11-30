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
            name: name,
            body: body,
            parameters: parameters,
            target: target,
        )
    end
end
