class Houndstooth::Environment
    # Analyses a `SemanticNode` tree and builds a set of types and definitions for an `Environment`.
    #
    # It's likely this entire class will be unnecessary when CTFE is implemented, but it's a nice
    # starting point for a basic typing checker.
    class Builder
        def initialize(root, environment)
            @root = root
            @environment = environment
        end

        # @return [SemanticNode]
        attr_reader :root

        # @return [Environment]
        attr_reader :environment

        def analyze(node: root, type_context: :root)
            # Note for type_context:
            #   - An instance of `DefinedType` means that new methods, subtypes etc encountered in
            #     the node tree will be defined there
            #   - The symbol `:root` means they're defined at the top-level of the environment
            #   - `nil` means types and methods cannot be defined here

            # TODO: consider if there's things which will "invalidate" a type context, turning it 
            # to nil - do we actually bother traversing into such things?
            # Even if we don't, the CTFE component presumably will

            case node
            when Houndstooth::SemanticNode::Body
                node.nodes.each do |child_node|
                    analyze(node: child_node, type_context: type_context)
                end

            when Houndstooth::SemanticNode::ClassDefinition
                name = constant_to_string(node.name)
                if name.nil?
                    Houndstooth::Errors::Error.new(
                        "Class name is not a constant",
                        [[node.name.ast_node.loc.expression, "not a constant"]]
                    ).push
                    return 
                end

                if node.superclass
                    superclass = constant_to_string(node.superclass)
                    if superclass.nil?
                        Houndstooth::Errors::Error.new(
                            "Superclass is not a constant",
                            [[node.superclass.ast_node.loc.expression, "not a constant"]]
                        ).push
                        return 
                    end
                else
                    superclass = "Object"
                end

                new_type = DefinedType.new(
                    path: append_type_and_rel_path(type_context, name),
                    superclass: PendingDefinedType.new(superclass)
                )
                environment.add_type(new_type)

                analyze(node: node.body, type_context: new_type)

            when Houndstooth::SemanticNode::ModuleDefinition
                name = constant_to_string(node.name)
                if name.nil?
                    Houndstooth::Errors::Error.new(
                        "Class name is not a constant",
                        [[node.name.ast_node.loc.expression, "not a constant"]]
                    ).push
                    return 
                end

                new_type = DefinedType.new(
                    path: append_type_and_rel_path(type_context, name),
                    eigen: PendingDefinedType.new("Module") # TODO: Is this correct?
                )
                environment.add_type(new_type)

                analyze(node: node.body, type_context: new_type)
            
            when Houndstooth::SemanticNode::MethodDefinition
                if node.target
                    # TODO
                    Houndstooth::Errors::Error.new(
                        "Method definitions with an explicit target are not yet supported",
                        [[node.target.ast_node.loc.expression, "unsupported"]]
                    ).push
                    return 
                end

                name = node.name
                
                # Look for signature comments attached to this definition - those beginning with:
                #   #:
                # The rest of the comment is an RBS signature attached to that method
                signatures = node.comments
                    .filter { |comment| comment.text.start_with?('#: ') }
                    .map do |comment|
                        TypeParser.parse_method_type(
                            comment.text[3...].strip,
                            method_definition_parameters: node.parameters
                        ) 
                    end

                if type_context.nil? || type_context == :root
                    # TODO method definitions should definitely be allowed at the root!
                    Houndstooth::Errors::Error.new(
                        "Method definition not allowed here",
                        [[node.ast_node.loc.keyword, "not allowed"]]
                    ).push
                    return
                end

                type_context.instance_methods << Method.new(name, signatures)
            end
        end

        # Tries to convert a series of nested `Constant`s into a String path.
        # 
        # If one of the items in the constant tree is not a `Constant` (or `ConstantRoot`), returns
        # nil. 
        #
        # @param [SemanticNode::Base] node
        # @return [String, nil]
        def constant_to_string(node)
            case node
            when Houndstooth::SemanticNode::Constant
                if node.target.nil?
                    node.name
                else
                    target_as_str = constant_to_string(node.target) or return nil
                    "#{target_as_str}::#{node.name}"
                end
            when Houndstooth::SemanticNode::ConstantBase
                ''
            else
                nil
            end
        end

        # Given a `DefinedType`, appends a relative path to its path.
        #
        # @param [DefinedType] type
        # @param [String] rel
        # @return [String]
        def append_type_and_rel_path(type, rel)
            if rel.start_with?('::')
                rel[2..]
            else
                if type == :root
                    rel
                else
                    "#{type.path}::#{rel}"
                end
            end
        end
    end
end
