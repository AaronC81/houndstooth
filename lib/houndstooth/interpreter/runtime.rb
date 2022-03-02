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

        def execute_block(block, lexical_context:, self_type:, self_object:)
            block.instructions.each do |inst|
                execute_instruction(inst, lexical_context: lexical_context, self_type: self_type, self_object: self_object)
            end
        end

        def execute_instruction(ins, lexical_context:, self_type:, self_object:)
            case ins
            when Houndstooth::Instructions::ConstantBaseAccessInstruction
                # There's no object we can use to represent the constant base, so let's go with a 
                # special symbol - it'll make it very obvious if it's being used somewhere it
                # shouldn't
                result_value = :constant_base

            when Houndstooth::Instructions::ConstantAccessInstruction
                if ins.target
                    # TODO: will only work with types, not actual constants
                    target_value = variables[ins.target]
                    if target_value == :constant_base
                        target = Houndstooth::Environment::BaseDefinedType.new
                    else
                        target = target_value.type
                    end
                else
                    target = lexical_context.uneigen
                end
                resolved = env.resolve_type(ins.name.to_s, type_context: env.resolve_type(target.uneigen))

                if resolved.nil?
                    Houndstooth::Errors::Error.new(
                        "No constant named `#{ins.name}` on `#{target.rbs}`",
                        [[ins.node.ast_node.loc.expression, "no such constant"]]
                    ).push

                    # Abandon
                    variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                    return
                end

                result_value = InterpreterObject.new(type: resolved, env: env)

            when Houndstooth::Instructions::TypeDefinitionInstruction
                if ins.target
                    Houndstooth::Errors::Error.new(
                        "namespace targets visited by interpreter are not supported",
                        [[node.ast_node.loc.expression, 'break up "class A::B" into separate definitions']],
                    ).push
                end

                # Because it can't be overridden (not yet supported above), we know that the type
                # is going to be defined on the lexical context
                type_being_defined = env.resolve_type("#{lexical_context.uneigen}::#{ins.name}").eigen
                type_being_defined_inst = type_being_defined.instantiate

                execute_block(
                    ins.body,
                    lexical_context: type_being_defined,
                    self_type: type_being_defined_inst,
                    self_object: InterpreterObject.new(
                        type: type_being_defined,
                        env: env,
                    ),
                )

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
