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

        def to_instructions(block)
            if target
                target.to_instructions(block)
                target_var = block.instructions.last.result
            else
                target_var = nil
            end

            mdi = I::MethodDefinitionInstruction.new(
                node: self,
                block: block,
                name: name,
                target: target_var,
                body: nil,
            )
            mdi.body =
                I::InstructionBlock.new(has_scope: true, parent: mdi).tap do |blk|
                    if !parameters.add_to_instruction_block(blk)
                        block.instructions << I::LiteralInstruction.new(node: self, block: block, value: nil)
                        return
                    end

                    if body
                        body.to_instructions(blk)
                    else
                        blk.instructions << I::LiteralInstruction.new(node: self, block: block, value: nil)
                    end
                end
            block.instructions << mdi
        end
    end

    module TypeDefinitionMixin
        def type_definition_instructions(block, kind)
            # Generate the name as instructions, but remove the last one to discover the name
            # (Because the name will lead up to the target, e.g. class A::B)
            # We measure how many instructions are generated to figure out if there was actually a
            # leading path
            instruction_count = block.instructions.length
            name.to_instructions(block)
            instruction_count = block.instructions.length - instruction_count
            unless block.instructions.last.is_a?(I::ConstantAccessInstruction)
                Houndstooth::Errors::Error.new(
                    "Type name must be a constant",
                    [[name.loc.expression, "unsupported"]]
                ).push
                return
            end
            type_name = block.instructions.pop.name.to_sym
            if instruction_count > 1
                type_target = block.instructions.last&.result
            else
                type_target = nil
            end

            if kind == :class
                # Generate superclass, or if there isn't one, use Object
                if superclass
                    superclass.to_instructions(block)
                    type_superclass = block.instructions.last.result
                else
                    block.instructions << I::ConstantBaseAccessInstruction.new(block: block, node: self)
                    block.instructions << I::ConstantAccessInstruction.new(
                        block: block,
                        node: self,
                        target: block.instructions.last.result,
                        name: :Object,
                    )
                    type_superclass = block.instructions.last.result
                end
            end

            # Build type
            tdi = I::TypeDefinitionInstruction.new(
                block: block,
                node: self,
                name: type_name,
                kind: kind,
                target: type_target,
                superclass: type_superclass,
                body: nil,
            )
            tdi.body =
                I::InstructionBlock.new(has_scope: true, parent: tdi).tap do |blk|
                    body&.to_instructions(blk)
                end

            block.instructions << tdi
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

        include TypeDefinitionMixin
        def to_instructions(block)
            type_definition_instructions(block, :class)
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

        include TypeDefinitionMixin
        def to_instructions(block)
            type_definition_instructions(block, :module)
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
