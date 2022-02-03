module Houndstooth::Checker
    module Preparation
        # Walks an instruction tree and assigns types to literal instructions. Assumes that the
        # stdlib has been loaded into the given environment.
        # Except in the case of internal errors, this won't introduce any type errors.
        # @param [Environment] env
        # @param [InstructionBlock] block
        def self.populate_literal_types(env, block)
            block.walk do |ins|
                if ins.is_a?(Houndstooth::Instructions::LiteralInstruction)
                    ins.result.type =
                        case ins.value
                        when Integer
                            env.resolve_type("Integer")
                        when Float
                            env.resolve_type("Float")
                        when String
                            env.resolve_type("String")
                        when Symbol
                            env.resolve_type("Symbol")
                        when TrueClass
                            env.resolve_type("TrueClass")
                        when FalseClass
                            env.resolve_type("FalseClass")
                        when NilClass
                            env.resolve_type("NilClass")
                        else
                            Houndstooth::Errors::Error.new(
                                "Internal bug - encountered a literal with an unknown type",
                                [[ins.node.ast_node.loc.expression, "literal"]]
                            ).push
                        end
                end
            end
        end
    end
end
