module Houndstooth
    class TypeChecker
        attr_reader :env

        def initialize(env)
            @env = env
        end

        def process_block(block, lexical_context:, self_type:)
            block.instructions.each do |ins|
                process_instruction(ins, lexical_context: lexical_context, self_type: self_type)
            end
        end

        def process_instruction(ins, lexical_context:, self_type:)
            case ins
            when Instructions::LiteralInstruction
                assign_type_to_literal_instruction(ins)
            
            when Instructions::ConditionalInstruction
                process_block(ins.true_branch, lexical_context: lexical_context, self_type: self_type)
                process_block(ins.false_branch, lexical_context: lexical_context, self_type: self_type)
                
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
                # Get type of target
                target_type = ins.block.variable_type_at!(ins.target, ins)

                # Look up method on target
                method = target_type.resolve_instance_method(ins.method_name)
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
                sig = method.resolve_matching_signature(arguments_with_types)
                if sig.nil?
                    error_message =
                        "`#{target_type.rbs}` method `#{ins.method_name}` has no signature matching the given arguments\n"

                    if method.signatures.any?
                        error_message += "Available signatures are:\n" \
                            + method.signatures.map { |s| "  - #{s.rbs}" }.join("\n")
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

                    # Assign result to untyped so type checking can continue
                    # TODO: create a special "abandoned" type specifically for this purpose
                    ins.type_change = Environment::UntypedType.new
                    
                    return
                end

                # Handle block
                catch :abort_block do
                    if sig.block_parameter && ins.method_block
                        # This method takes a block, and was given one
                        # Add parameter types
                        throw :abort_block \
                            if !add_parameter_type_instructions(ins, ins.method_block, sig.block_parameter.type)

                        # Recurse type checking into it
                        process_block(ins.method_block, lexical_context: lexical_context, self_type: self_type)

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
                    ins.type_change = env.resolve_type(target_type.uneigen)
                else
                    # No special cases, set result variable to return type
                    ins.type_change = sig.return_type
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
                new_type = "#{target.uneigen}::#{ins.name}"
                resolved = env.resolve_type(new_type)

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

                ins.type_change = resolved.eigen

            when Instructions::SelfInstruction
                ins.type_change = self_type

            when Instructions::TypeDefinitionInstruction
                if ins.target
                    base_type = ins.block.variable_type_at!(ins.target, ins) 
                else
                    base_type = lexical_context
                end

                type_being_defined = env.resolve_type("#{base_type.uneigen}::#{ins.name}").eigen

                process_block(
                    ins.body,
                    lexical_context: type_being_defined,
                    self_type: type_being_defined,
                )
                
                # Returns the just-defined type
                ins.type_change = type_being_defined

            when Instructions::MethodDefinitionInstruction
                # Look up this method in the environment, so we can find its type signature
                # Where's it defined? The only allowed explicit target currently is `self`, so if
                # that's given...
                if !ins.target.nil?
                    # ...then it's defined on `self`
                    inner_self_type = self_type
                    method = inner_self_type.resolve_instance_method(ins.name)
                else
                    # Otherwise it's defined on the instance of `self`
                    inner_self_type = env.resolve_type(self_type.uneigen)
                    method = inner_self_type.resolve_instance_method(ins.name)
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

                    # Recurse into body
                    process_block(
                        ins.body,
                        self_type: inner_self_type,
                        lexical_context: lexical_context,
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
                ins.type_change = env.resolve_type("Symbol")

            when Instructions::ToStringInstruction
                ins.type_change = env.resolve_type("String")

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
