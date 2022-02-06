module Houndstooth::SemanticNode
    # An integer literal.
    class IntegerLiteral < Base
        # @return [Integer]
        attr_accessor :value

        register_ast_converter :int do |ast_node|
            IntegerLiteral.new(ast_node: ast_node, value: ast_node.to_a.first)
        end

        def to_instructions(block)
            block.instructions << I::LiteralInstruction.new(block: block, node: self, value: value)
        end
    end

    # A floating-point number literal.
    class FloatLiteral < Base
        # @return [Float]
        attr_accessor :value

        register_ast_converter :float do |ast_node|
            FloatLiteral.new(ast_node: ast_node, value: ast_node.to_a.first)
        end

        def to_instructions(block)
            block.instructions << I::LiteralInstruction.new(block: block, node: self, value: value)
        end
    end

    # A string literal, possibly with interpolated components.
    class StringLiteral < Base
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

        def to_instructions(block)
            # There are a few different ways to compile this, depending on what the string's made
            # up of...
            if components.all? { |c| c.is_a?(String) }
                # All literals
                value = components.join
                block.instructions << I::LiteralInstruction.new(block: block, node: self, value: value)
            else
                # We need to actually generate instructions to concatenate the strings at runtime
                # First evaluate each part of the string into a variable
                string_part_variables = components.map do |c|
                    if c.is_a?(String)
                        block.instructions << I::LiteralInstruction.new(block: block, node: self, value: c)
                    else
                        c.to_instructions(block)
                        block.instructions << I::ToStringInstruction.new(
                            block: block,
                            node: c,
                            target: block.instructions.last.result,
                        )
                    end
                    block.instructions.last.result
                end

                # Now generate code to concatenate these variables together
                previous_variable = string_part_variables.first
                string_part_variables[1..].each do |variable|
                    block.instructions << I::SendInstruction.new(
                        block: block, 
                        node: self,
                        target: previous_variable,
                        method_name: :+,
                        arguments: [I::PositionalArgument.new(variable)],
                    )
                    previous_variable = block.instructions.last.result
                end
            end
        end
    end

    # A symbol literal, possibly with interpolated components.
    class SymbolLiteral < Base
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

        def to_instructions(block)
            # This logic is identical to translating a string literal - if it's all symbols we'll do
            # it directly, otherwise we'll pretend we're a string and hand it off
            if components.all? { |c| c.is_a?(String) }
                # All literals
                value = components.join
                block.instructions << I::LiteralInstruction.new(block: block, node: self, value: value.to_sym)
            else
                # Pretend we're a string, and convert to a symbol with a call at the end
                # Not 100% equivalent in terms of allocations, but Good Enough
                StringLiteral.new(ast_node: ast_node, components: components).to_instructions(block)
                block.instructions << I::SendInstruction.new(
                    block: block,
                    node: self,
                    target: block.instructions.last.result,
                    method_name: :to_sym,
                )
            end
        end 
    end

    # An array literal.
    class ArrayLiteral < Base
        # @return [<SemanticNode>]
        attr_accessor :nodes

        register_ast_converter :array do |ast_node|
            ArrayLiteral.new(
                ast_node: ast_node,
                nodes: ast_node.to_a.map { |node| from_ast(node) }
            )
        end
    end

    # A hash literal.
    class HashLiteral < Base
        # @return [<(SemanticNode, SemanticNode)>]
        attr_accessor :pairs

        register_ast_converter :hash do |ast_node|
            HashLiteral.new(
                ast_node: ast_node,
                pairs: ast_node.to_a.map { |pair| pair.to_a.map { from_ast(_1) } }
            )
        end
    end

    # A range literal.
    class RangeLiteral < Base
        # @return [SemanticNode, nil]
        attr_accessor :first

        # @return [SemanticNode, nil]
        attr_accessor :last

        # @return [bool]
        attr_accessor :inclusive

        register_ast_converter :irange, :erange do |ast_node|
            first, last = ast_node.to_a.map { from_ast(_1) if _1 }

            RangeLiteral.new(
                ast_node: ast_node,
                first: first,
                last: last,
                inclusive: (ast_node.type == :irange),
            )
        end
    end
end
