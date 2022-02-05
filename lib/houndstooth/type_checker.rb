module Houndstooth
    class TypeChecker
        attr_reader :env

        def initialize(env)
            @env = env
        end

        def process_block(block)
            block.instructions.each do |ins|
                process_instruction(ins)
            end
        end

        def process_instruction(ins)
            case ins
            when Instructions::LiteralInstruction
                assign_type_to_literal_instruction(ins)
            when Instructions::ConditionalInstruction
                process_block(ins.true_branch)
                process_block(ins.false_branch)
            end
        end

        # Given a `LiteralInstruction`, assigns a result type based on the value. Assumes that the
        # stdlib is loaded into the environment.
        # @param [LiteralInstruction] ins
        def assign_type_to_literal_instruction(ins)
            ins.type_change =
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
