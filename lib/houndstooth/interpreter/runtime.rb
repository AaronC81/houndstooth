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

        def execute_block(block, lexical_context:, self_type:, self_object:, type_arguments:)
            block.instructions.each do |inst|
                execute_instruction(inst, lexical_context: lexical_context, self_type: self_type, self_object: self_object, type_arguments: type_arguments)
            end
        end

        def execute_instruction(ins, lexical_context:, self_type:, self_object:, type_arguments:)
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
                    target = lexical_context
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

                result_value = InterpreterObject.new(type: resolved.eigen, env: env)

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
                    type_arguments: type_arguments,
                )

                result_value = variables[ins.body.instructions.last.result]

            when Houndstooth::Instructions::MethodDefinitionInstruction
                method, _ = ins.resolve_method_and_type(self_type, env)

                # Associate instruction block with environment
                method.instruction_block = ins.body
                
                # Return name of defined method
                result_value = InterpreterObject.from_value(value: ins.name, env: env)

            when Houndstooth::Instructions::LiteralInstruction
                result_value = InterpreterObject.from_value(value: ins.value, env: env)

            when Houndstooth::Instructions::SelfInstruction
                result_value = self_object

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

                if meth.nil?
                    Houndstooth::Errors::Error.new(
                        "`#{target}` has no method named `#{ins.method_name}`",
                        [[ins.node.ast_node.loc.expression, 'no such method']],
                    ).push

                    # Abandon
                    variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                    return
                end
                
                if meth.const.nil?
                    Houndstooth::Errors::Error.new(
                        "Cannot call non-const method `#{meth.name}` on `#{target}` from const context",
                        [[ins.node.ast_node.loc.expression, 'call is not const']],
                    ).push

                    # Abandon
                    variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                    return
                end

                # Parse type arguments
                type_args = Houndstooth::Environment::TypeParser.parse_type_arguments(env, ins.type_arguments, type_arguments)
                    .map { |t| t.substitute_type_parameters(nil, type_arguments) }

                # Crudely find the best signature based on the number of type parameters - this is
                # extremely wonky!
                type_params = meth.signatures.find { |sig| sig.type_parameters.length == type_args.length }&.type_parameters
                raise 'internal error: no const signature matching number of type parameters' if type_params.nil?
                type_arguments = type_arguments.merge(type_params.zip(type_args).to_h)

                if meth.const_internal?
                    # Look up, call, and set result
                    begin
                        definition = const_internal.method_definitions[meth]
                        raise "internal error: `#{meth.name}` on `#{target}` is missing const-internal definition" if definition.nil?

                        # It's OK for const-internal definitions to just execute the block directly
                        # on this runtime, since the instruction generator will have sorted out any
                        # local scoping with overlapping names for us
                        result_value = definition.(
                            target, *args,
                            type_arguments: type_arguments,
                            call_block: ->(args) do
                                # `call_method`'s arguments expect Variables... but we don't have
                                # any here! The value came from a magical internal source.
                                # Instead, we can just make up some new ones; it'll be fine!
                                args = args.map do |arg|
                                    var = Houndstooth::Instructions::Variable.new
                                    variables[var] = arg
                                    Houndstooth::Instructions::PositionalArgument.new(var)
                                end

                                call_method(
                                    block: ins.method_block,
                                    arguments: args,
                                    loc: ins.node.ast_node.loc,
                                    type_arguments: type_arguments,
                                    target: self_object,
                                    lexical_context: lexical_context,
                                )
                            end,
                        )
                    rescue => e
                        raise e if $cli_options[:fatal_interpreter]
                        
                        Houndstooth::Errors::Error.new(
                            "Interpreter runtime error: #{e}\n       " \
                            "(run with --fatal-interpreter to exit with backtrace on first error)",
                            [[ins.node.ast_node.loc.expression, 'occurred within this call']],
                        ).push

                        # Abandon
                        variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                        return
                    end
                else
                    # Check there's actually a definition
                    if meth.instruction_block.nil?
                        Houndstooth::Errors::Error.new(
                            "`#{meth.name}` on `#{target}` has not been defined yet",
                            [[ins.node.ast_node.loc.expression, 'no definition of method called here']],
                        ).push

                        # Abandon
                        variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                        return
                    end

                    call_result = call_method(
                        block: meth.instruction_block,
                        arguments: ins.arguments,
                        loc: ins.node.ast_node.loc,
                        type_arguments: type_arguments,
                        target: target,
                        lexical_context: lexical_context,
                    )
                    if call_result == false
                        # Abandon
                        variables[ins.result] = InterpreterObject.from_value(value: nil, env: env)
                    else
                        result_value = call_result
                    end
                end
                
            when Houndstooth::Instructions::ConditionalInstruction
                condition = variables[ins.condition]
                if condition.truthy?
                    execute_block(ins.true_branch, lexical_context: lexical_context, self_type: self_type, self_object: self_object, type_arguments: type_arguments)
                    result_value = variables[ins.true_branch.instructions.last.result]
                else
                    execute_block(ins.false_branch, lexical_context: lexical_context, self_type: self_type, self_object: self_object, type_arguments: type_arguments)
                    result_value = variables[ins.false_branch.instructions.last.result]
                end

            when Houndstooth::Instructions::ToStringInstruction
                obj = variables[ins.target]
                result_value = obj.ruby_inspect
                result_value = InterpreterObject.from_value(value: result_value, env: env)
            else
                raise "internal error: don't know how to interpret #{ins.class.name}"
            end

            variables[ins.result] = result_value
        end

        # Finds instructions at the very top level of a program to execute, and executes them. Not
        # all instructions in the given block will be executed.
        def execute_from_top_level(block)
            # Run the interpreter on top-level definitions
            # TODO: ...and also particular marked top-level sends (see notes in Obsidian)
            # Because we don't allow definitions to have targets yet, this is fine - any nodes used to
            # build up to the definition do not matter
            instructions_to_interpret = []
            block.instructions.each do |ins|
                if ins.is_a?(Houndstooth::Instructions::TypeDefinitionInstruction)
                    instructions_to_interpret << ins
                end
            end
            instructions_to_interpret.each do |ins|
                ins.mark_const_considered
                execute_instruction(
                    ins,
                    self_object: nil, # TODO
                    self_type: nil, # TODO
                    lexical_context: Houndstooth::Environment::BaseDefinedType.new,
                    type_arguments: {},
                )
            end
        end

        def call_method(block:, arguments:, loc:, type_arguments:, target:, lexical_context:)
            # Create a new runtime frame to call this method
            child_runtime = Runtime.new(env: env)

            # Populate arguments
            if arguments.length != block.parameters.length
                Houndstooth::Errors::Error.new(
                    "Wrong number of arguments to interpreter method call",
                    [[loc.expression, "got #{arguments.length}, expected #{block.parameters.length}"]],
                ).push

                # Abandon
                return false
            end

            arguments.zip(block.parameters).each do |arg, param_var|
                unless arg.is_a?(Houndstooth::Instructions::PositionalArgument)
                    Houndstooth::Errors::Error.new(
                        "Unsupported argument type used - only positional arguments are supported",
                        [[loc.expression, 'unsupported']],
                    ).push

                    # Abandon
                    return false
                end

                # Inject variables into the runtime to set
                child_runtime.variables[param_var] = variables[arg.variable]
            end

            # Execute body and set return value
            child_runtime.execute_block(
                block,
                lexical_context: lexical_context,
                self_object: target,
                self_type: target.type,
                type_arguments: type_arguments,
            )
            child_runtime.variables[block.instructions.last.result]
        end
    end
end
