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
                        "`#{target_type.rbs}` method `#{ins.method_name}` has no signature matching the given arguments\n" \
                        "Available signatures are:\n" \
                        + method.signatures.map { |s| "  - #{s.rbs}" }.join("\n")

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

                # Set result variable to return type
                ins.type_change = sig.return_type

            when Instructions::ConstantBaseAccessInstruction
                ins.type_change = Environment::BaseDefinedType.new

            when Instructions::ConstantAccessInstruction
                if ins.target
                    # TODO: will only work with types, not actual constants
                    target = ins.block.variable_type_at!(ins.target, ins)
                else
                    target = ins.block.lexical_context!
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
                ins.type_change = ins.block.self_type!

            when Instructions::TypeDefinitionInstruction
                # TODO: just skip over these for now

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
    end
end
