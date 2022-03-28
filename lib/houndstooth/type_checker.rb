module Houndstooth
    class TypeChecker
        attr_reader :env

        def initialize(env)
            @env = env
        end

        def process_block(block, lexical_context:, self_type:, const_context:, type_parameters:)
            block.environment = env
            block.instructions.each do |ins|
                process_instruction(ins,
                    lexical_context: lexical_context,
                    self_type: self_type,
                    const_context: const_context,
                    type_parameters: type_parameters,
                )
            end
        end

        def process_instruction(ins, lexical_context:, self_type:, const_context:, type_parameters:)                        
            case ins
            when Instructions::LiteralInstruction
                assign_type_to_literal_instruction(ins)
            
            when Instructions::ConditionalInstruction
                # Special case - did the conditional of this `if` statement come from an `is_a?`
                # call immediately preceding it?
                index = ins.block.instructions.index { _1 == ins }
                if index != 0
                    last_ins = ins.block.instructions[index - 1]
                    if last_ins.is_a?(Instructions::SendInstruction) \
                        && last_ins.method_name == :is_a? \
                        && last_ins.result == ins.condition \
                        && last_ins.target.ruby_identifier \
                        && last_ins.arguments.length == 1

                        # Yep, we just checked the type of a local variable!
                        # In the true branch, we can refine the type
                        # What was the argument type? Uneigen it to get the type of the variable
                        arg_var = last_ins.arguments.first.variable
                        arg_type = ins.block.variable_type_at!(arg_var, ins)
                        checked_var_type = env.resolve_type(arg_type.type.uneigen).instantiate

                        ins.true_branch.type_refinements[last_ins.target] = checked_var_type
                    end
                end

                process_block(ins.true_branch, lexical_context: lexical_context, self_type: self_type, const_context: const_context, type_parameters: type_parameters)
                process_block(ins.false_branch, lexical_context: lexical_context, self_type: self_type, const_context: const_context, type_parameters: type_parameters)
                
                # A conditional could return either of its branches
                ins.type_change = Environment::UnionType.new([
                    ins.true_branch.return_type!,
                    ins.false_branch.return_type!,
                ]).simplify
            
            when Instructions::AssignExistingInstruction
                # If the assignment is to a different variable, set a typechange
                if ins.result != ins.variable
                    ins.type_change = ins.block.variable_type_at!(ins.variable, ins)
                end

            when Instructions::SendInstruction
                # Parse type arguments, if any
                type_args = Environment::TypeParser.parse_type_arguments(env, ins.type_arguments, type_parameters)

                # Get type of target
                target_type = ins.block.variable_type_at!(ins.target, ins)

                # Look up method on target
                method = target_type.resolve_instance_method(ins.method_name, env)
                if method.nil?
                    Houndstooth::Errors::Error.new(
                        "`#{target_type.rbs}` has no method named `#{ins.method_name}`",
                        [[ins.node.ast_node.loc.expression, "no such method"]]
                    ).push

                    # Assign result to untyped so type checking can continue
                    # TODO: create a special "abandoned" type specifically for this purpose
                    ins.type_change = Environment::UntypedType.new
                    
                    return
                end

                # Get type of all arguments
                arguments_with_types = ins.arguments.map do |arg|
                    [arg, ins.block.variable_type_at!(arg.variable, ins)]
                end

                # Resolve the best method signature with these
                sig = method.resolve_matching_signature(target_type, arguments_with_types, type_args)
                if sig.nil?
                    # Special case - if the node isn't a send, then it's a generated insertion to
                    # an array
                    if !ins.node.is_a?(Houndstooth::SemanticNode::Send)
                        # TODO: improve error
                        Houndstooth::Errors::Error.new(
                            "Incorrect type of element in array literal",
                            [[ins.node.ast_node.loc.expression, "type does not match annotation"]]
                        ).push
                    else
                        error_message =
                            "`#{target_type.rbs}` method `#{ins.method_name}` has no signature matching the given arguments\n"

                        if method.signatures.any?
                            error_message += "Available signatures are:\n" \
                                + method.signatures.map { |s| "  - #{s.substitute_type_parameters(target_type, Hash.new).rbs}" }.join("\n")
                        else
                            error_message += "Method has no signatures - did you use a #: comment?"
                        end

                        Houndstooth::Errors::Error.new(
                            error_message,
                            # TODO: feels a bit dodgy
                            [[ins.node.ast_node.loc.expression, "no matching signature"]] \
                                + ins.node.arguments.zip(arguments_with_types).map do |node, (_, t)|
                                    [node.node.ast_node.loc.expression, "argument type is `#{t.rbs}`"]
                                end
                        ).push
                    end

                    # Assign result to untyped so type checking can continue
                    # TODO: create a special "abandoned" type specifically for this purpose
                    ins.type_change = Environment::UntypedType.new
                    
                    return
                end

                # Resolve type arguments - don't need to perform length check here, since the sig
                # wouldn't have matched if the lengths mismatched
                call_type_args = sig.type_parameters.zip(type_args).to_h
                sig = sig.substitute_type_parameters(target_type, call_type_args)

                # Handle block
                catch :abort_block do
                    if sig.block_parameter && ins.method_block
                        # This method takes a block, and was given one
                        # Add parameter types
                        throw :abort_block \
                            if !add_parameter_type_instructions(ins, ins.method_block, sig.block_parameter.type)

                        # Recurse type checking into it
                        # We don't support overridden block self types, so we need to special-case
                        # this for `define_method`, where the block's `self` is uneigened
                        # `define_method` also strips constness
                        if method == env.resolve_type('::Module').resolve_instance_method(:define_method, env)
                            # HACK: Won't work with generics
                            inner_self_type = env.resolve_type(self_type.type.uneigen).instantiate
                            inner_const_context = false
                        else
                            inner_self_type = self_type
                            inner_const_context = const_context
                        end
                        process_block(ins.method_block, lexical_context: lexical_context, self_type: inner_self_type, const_context: inner_const_context, type_parameters: type_parameters)

                        # Check return type
                        if !sig.block_parameter.type.return_type.accepts?(ins.method_block.return_type!)
                            Houndstooth::Errors::Error.new(
                                "Incorrect return type for block, expected `#{sig.block_parameter.type.return_type.rbs}`",
                                [[
                                    ins.method_block.instructions.last.node.ast_node.loc.expression,
                                    "got `#{ins.method_block.return_type!.rbs}`"
                                ]]
                            ).push
                            throw :abort_block
                        end

                    elsif sig.block_parameter && !ins.method_block
                        # This method takes a block, but wasn't given one
                        # If the block is not optional, error
                        if !sig.block_parameter.optional?
                            Houndstooth::Errors::Error.new(
                                "`#{target_type.rbs}` method `#{ins.method_name}` requires a block, but none was given",
                                [[ins.node.ast_node.loc.expression, "expected block"]]
                            ).push
                        end
                    elsif !sig.block_parameter && ins.method_block
                        # This method doesn't take a block, but was given one
                        # That's not allowed!
                        # (Well, Ruby allows it, but it doesn't make sense for us - 99% of the time,
                        # this will be a bug)
                        if ins.method_block
                            Houndstooth::Errors::Error.new(
                                "`#{target_type.rbs}` method `#{ins.method_name}` does not accept a block",
                                [[ins.node.ast_node.loc.expression, "unexpected block"]]
                            ).push
                        end
                    end
                end

                # Check for return type special cases
                case sig.return_type
                when Environment::SelfType
                    ins.type_change = target_type
                when Environment::InstanceType
                    ins.type_change = env.resolve_type(target_type.type.uneigen).instantiate(target_type.type_arguments)
                else
                    # No special cases, set result variable to return type
                    ins.type_change = sig.return_type
                end

                # If we're in a const context, check that the target method is const
                if const_context && !method.const?
                    Houndstooth::Errors::Error.new(
                        "`#{target_type.rbs}` method `#{ins.method_name}` is not const, so cannot be called from a const context",
                        [[ins.node.ast_node.loc.expression, "call inside a const context"]]
                    ).push
                end
                
                # If this method is const-required, check that the call was const-considered, or the
                # method we're currently in is const-required
                if method.const_required? && !ins.const_considered?
                    Houndstooth::Errors::Error.new(
                        "`#{target_type.rbs}` method `#{ins.method_name}` is const-required, but this call is not within a const-required context",
                        [[ins.node.ast_node.loc.expression, "call outside a const context"]]
                    ).push
                end

            when Instructions::ConstantBaseAccessInstruction
                ins.type_change = Environment::BaseDefinedType.new

            when Instructions::ConstantAccessInstruction
                if ins.target
                    # TODO: will only work with types, not actual constants
                    target = ins.block.variable_type_at!(ins.target, ins)
                else
                    target = lexical_context
                end
                resolved = env.resolve_type(ins.name.to_s, type_context: env.resolve_type(target.uneigen))

                if resolved.nil?
                    Houndstooth::Errors::Error.new(
                        "No constant named `#{ins.name}` on `#{target.rbs}`",
                        [[ins.node.ast_node.loc.expression, "no such constant"]]
                    ).push

                    # Assign result to untyped so type checking can continue
                    # TODO: another use for "abandoned" type
                    ins.type_change = Environment::UntypedType.new
                    return
                end

                # Check type parameter numbers (even if the type doesn't have any - we don't want
                # to allow type arguments when none are expected)
                el = resolved.type_parameters.length
                gl = ins.type_arguments.length
                if el != gl
                    Houndstooth::Errors::Error.new(
                        "Insufficient type arguments for `#{ins.name}` (expected #{el}, got #{gl})",
                        [[ins.node.ast_node.loc.expression, "incorrect number of arguments"]]
                    ).push

                    # Assign result to untyped so type checking can continue
                    # TODO: another use for "abandoned" type
                    ins.type_change = Environment::UntypedType.new
                    return
                end

                # Does the type require type parameters?
                if resolved.type_parameters.any?
                    # Yep - parse them
                    type_args = Environment::TypeParser.parse_type_arguments(env, ins.type_arguments, type_parameters)
                else
                    type_args = []
                end

                ins.type_change = resolved.eigen.instantiate(type_args)

            when Instructions::SelfInstruction
                ins.type_change = self_type

            when Instructions::TypeDefinitionInstruction
                if ins.target
                    base_type = ins.block.variable_type_at!(ins.target, ins) 
                else
                    base_type = lexical_context
                end

                type_being_defined = env.resolve_type("#{base_type.uneigen}::#{ins.name}").eigen
                type_being_defined_inst = type_being_defined.instantiate

                process_block(
                    ins.body,
                    lexical_context: type_being_defined,
                    self_type: type_being_defined_inst,
                    # Type definitions bodies are always const
                    const_context: true,
                    type_parameters: type_parameters + type_being_defined.type_parameters,
                )
                
                # Returns the just-defined type
                ins.type_change = type_being_defined_inst

            when Instructions::MethodDefinitionInstruction
                method, inner_self_type = ins.resolve_method_and_type(self_type, env)

                # If this method is const-required, mark its body as const-considered
                if method.const_required?
                    ins.body.mark_const_considered
                end

                # Does it have any signatures?
                if method.signatures.empty?
                    Houndstooth::Errors::Error.new(
                        "No signatures provided",
                        [[ins.node.ast_node.loc.expression, "no signatures"]]
                    ).push
                end

                # Check each signature
                method.signatures.map do |sig|
                    # Assign parameter types
                    number_of_type_ins = add_parameter_type_instructions(ins, ins.body, sig)
                    if number_of_type_ins == false
                        next
                    end 

                    # Recurse into body
                    process_block(
                        ins.body,
                        self_type: inner_self_type,
                        lexical_context: lexical_context,
                        # Method definition bodies are const iff the method being defined is
                        const_context: method.const?,
                        type_parameters: type_parameters + sig.type_parameters,
                    )

                    # Check return type
                    if !sig.return_type.accepts?(ins.body.return_type!)
                        Houndstooth::Errors::Error.new(
                            "Incorrect return type for method, expected `#{sig.return_type.rbs}`",
                            [[
                                ins.body.instructions.last.node.ast_node.loc.expression,
                                "got `#{ins.body.return_type!.rbs}`"
                            ]]
                        ).push
                    end

                    # If there's more than one, remove type instructions so the next loop can add
                    # them again
                    # (We could remove them if there's only one too, but it's handy to leave in for
                    # debugging)
                    if method.signatures.length > 1
                        number_of_type_ins.times { ins.body.instructions.shift }
                    end
                end

                # Returns a symbol of the method's name
                ins.type_change = env.resolve_type("Symbol").instantiate

            when Instructions::ToStringInstruction
                ins.type_change = env.resolve_type("String").instantiate

            when Instructions::InstanceVariableReadInstruction
                var_type = self_type.type.resolve_instance_variable(ins.name)
                if var_type.nil?
                    Houndstooth::Errors::Error.new(
                        "Instance variable #{ins.name} is not defined",
                        [[ins.node.ast_node.loc.expression, "undefined"]]
                    ).push
                    ins.type_change = Environment::UntypedType.new
                    return
                end

                ins.type_change = var_type

            when Instructions::InstanceVariableWriteInstruction
                var_type = self_type.type.resolve_instance_variable(ins.name)
                if var_type.nil?
                    Houndstooth::Errors::Error.new(
                        "Instance variable #{ins.name} is not defined",
                        [[ins.node.ast_node.loc.expression, "undefined"]]
                    ).push
                    ins.type_change = Environment::UntypedType.new
                    return
                end

                value_type = ins.block.variable_type_at!(ins.value, ins)

                if !var_type.accepts?(value_type)
                    Houndstooth::Errors::Error.new(
                        "Cannot assign `#{value_type.rbs}` to #{ins.name}",
                        [[ins.node.ast_node.loc.expression, "Expected `#{var_type.rbs}`"]]
                    ).push
                end

                ins.type_change = var_type

            else
                raise "internal error: don\'t know how to type check #{ins.class.to_s}"
            end
        end

        # Given a `LiteralInstruction`, assigns a result type based on the value. Assumes that the
        # stdlib is loaded into the environment.
        # @param [LiteralInstruction] ins
        def assign_type_to_literal_instruction(ins)
            ins.type_change =
                case ins.value
                when Integer
                    env.resolve_type("Integer").instantiate
                when Float
                    env.resolve_type("Float").instantiate
                when String
                    env.resolve_type("String").instantiate
                when Symbol
                    env.resolve_type("Symbol").instantiate
                when TrueClass
                    env.resolve_type("TrueClass").instantiate
                when FalseClass
                    env.resolve_type("FalseClass").instantiate
                when NilClass
                    env.resolve_type("NilClass").instantiate
                else
                    Houndstooth::Errors::Error.new(
                        "Internal bug - encountered a literal with an unknown type",
                        [[ins.node.ast_node.loc.expression, "literal"]]
                    ).push
                end
        end

        # Inserts instructions into the beginning of block to assign types to a set of parameter
        # variables.
        #
        # @param [Instruction] ins The instruction this is relevant to. Only used for error
        #   reporting and for the nodes of the new instructions.
        # @param [InstructionBlock] block The instruction block to prepend the new instructions to.
        # @param [MethodType] method_type The method type to retrieve parameter types from.
        # @return [Integer, false] False if an error occurred, otherwise the number of instructions
        #   added to the beginning.
        def add_parameter_type_instructions(ins, block, method_type)
            # Check parameter count
            # TODO: this won't work if we support other kinds of parameter
            expected_ps = method_type.positional_parameters
            got_ps = block.parameters
            expected_l = expected_ps.length
            got_l = got_ps.length
            if expected_l != got_l
                Houndstooth::Errors::Error.new(
                    "Incorrect number of parameters (expected #{expected_l}, got #{got_l})",
                    [[ins.node.ast_node.loc.expression, "incorrect parameters"]]
                ).push
                return false
            end

            # Insert an instruction to assign each parameter's type
            expected_ps.zip(got_ps).each do |type_param, var|
                i = Instructions::AssignExistingInstruction.new(
                    block: block,
                    node: ins.node,
                    result: var,
                    variable: var,
                )
                i.type_change = type_param.type
                block.instructions.unshift(i)
            end

            expected_ps.length
        end
    end
end
