module Houndstooth::SemanticNode
    # A method definition. Used for both standard method definitions (`def x()`) or definitions
    # on a singleton (`def something.x()`).
    class MethodDefinition < Base
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
            comments = shift_comments(ast_node)

            body = from_ast(body) if body
            parameters = from_ast(parameters)

            MethodDefinition.new(
                ast_node: ast_node,
                comments: comments,

                name: name,
                body: body,
                parameters: parameters,
                target: nil,
            )
        end

        register_ast_converter :defs do |ast_node|
            target, name, parameters, body = *ast_node
            comments = shift_comments(ast_node)

            target = from_ast(target)
            body = from_ast(body) if body
            parameters = from_ast(parameters)

            MethodDefinition.new(
                ast_node: ast_node,
                comments: comments,

                name: name,
                body: body,
                parameters: parameters,
                target: target,
            )
        end
    end

    # A class definition.
    class ClassDefinition < Base
        # @return [SemanticNode]
        attr_accessor :name

        # @return [SemanticNode, nil]
        attr_accessor :superclass

        # @return [SemanticNode, nil]
        attr_accessor :body

        register_ast_converter :class do |ast_node|
            name, superclass, body = *ast_node
            comments = shift_comments(ast_node)

            name = from_ast(name)
            superclass = from_ast(superclass) if superclass
            body = from_ast(body) if body

            ClassDefinition.new(
                ast_node: ast_node,
                comments: comments,

                name: name,
                superclass: superclass,
                body: body,
            )
        end
    end

    # A singleton class accessor: `class << x`.
    class SingletonClass < Base
        # @return [SemanticNode]
        attr_accessor :target

        # @return [SemanticNode, nil]
        attr_accessor :body

        register_ast_converter :sclass do |ast_node|
            target, body = *ast_node

            target = from_ast(target)
            body = from_ast(body) if body

            SingletonClass.new(
                ast_node: ast_node,                
                target: target,
                body: body,
            )
        end
    end

    # A module definition.
    class ModuleDefinition < Base
        # @return [SemanticNode]
        attr_accessor :name

        # @return [SemanticNode, nil]
        attr_accessor :body

        register_ast_converter :module do |ast_node|
            name, body = *ast_node
            comments = shift_comments(ast_node)

            name = from_ast(name)
            body = from_ast(body) if body

            ModuleDefinition.new(
                ast_node: ast_node,
                comments: comments,
                
                name: name,
                body: body,
            )
        end
    end

    # An alias.
    #
    # Aliases are usually between statically-named methods given with just identifiers, but they
    # can also be between methods named with dynamic symbols, and even between global variables.
    class Alias < Base
        # @return [SemanticNode]
        attr_accessor :from

        # @return [SemanticNode]
        attr_accessor :to

        register_ast_converter :alias do |ast_node|
            to, from = ast_node.to_a.map { from_ast(_1) }

            Alias.new(
                ast_node: ast_node,
                from: from,
                to: to,
            )
        end
    end
end
