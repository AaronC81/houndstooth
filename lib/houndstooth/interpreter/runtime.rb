require_relative 'const_internal'

module Houndstooth::Interpreter
    class Runtime
        def initialize(env:)
            @variables = {}
            @env = env
            @const_internal = ConstInternal.new(env: env)
        end

        # @return [{Variable => InterpreterObject}]
        attr_accessor :variables

        # @return [Environment]
        attr_accessor :env

        # @return [ConstInternal]
        attr_accessor :const_internal

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

            when Houndstooth::Instructions::SendInstruction
                target = variables[ins.target]
                meth = target.type.resolve_instance_method(ins.method_name, env)
                args = ins.arguments.map do |arg|
                    if arg.is_a?(Houndstooth::Instructions::PositionalArgument)
                        variables[arg.variable]
                    else
                        raise 'internal error: unimplemented arg should\'ve been caught earlier than interpreter'
                    end
                end
                
                if meth.const.nil?
                    Houndstooth::Errors::Error.new(
                        "Cannot call non-const method `#{meth.name}` on `#{target.rbs}` from const context",
                        [[node.ast_node.loc.expression, 'call is not const']],
                    ).push

                    # Abandon
                    variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                    return
                elsif meth.const_internal?
                    # Look up, call, and set result
                    result_value = const_internal.method_definitions[meth].(target, *args)
                else
                    Houndstooth::Errors::Error.new(
                        "Unimplemented const type #{meth.const}",
                        [[node.ast_node.loc.expression, 'unimplemented const type']],
                    ).push

                    # Abandon
                    variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                    return
                end
                
            else
                raise "internal error: don't know how to interpret #{ins.class.name}"
            end

            variables[ins.result] = result_value
        end
    end
end
