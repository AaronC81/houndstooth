module Houndstooth::Interpreter
    class Runtime
        def initialize(env:)
            @variables = {}
            @env = env
        end

        # @return [{Variable => InterpreterObject}]
        attr_accessor :variables

        # @return [Environment]
        attr_accessor :env

        def execute_block(block)
            block.instructions.each do |inst|
                execute_instruction(inst)
            end
        end

        def execute_instruction(ins)
            case ins
            when Houndstooth::Instructions::LiteralInstruction
                result_value = InterpreterObject.from_value(value: ins.value, env: env)

            when Houndstooth::Instructions::AssignExistingInstruction
                result_value = variables[ins.variable]
                
            else
                raise "internal error: don't know how to interpret #{ins.class.name}"
            end

            variables[ins.result] = result_value
        end
    end
end
