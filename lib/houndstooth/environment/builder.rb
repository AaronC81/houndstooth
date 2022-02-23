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
                is_magic_basic_object = node.comments.find { |c| c.text.strip == "#!magic basicobject" }

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
                    # Special case used only for BasicObject
                    if is_magic_basic_object
                        superclass = nil 
                    else
                        superclass = "Object"
                    end
                end

                new_type = DefinedType.new(
                    node: node,
                    path: append_type_and_rel_path(type_context, name),
                    type_parameters: type_parameter_definitions(node),
                    superclass: superclass ? PendingDefinedType.new(superclass) : nil
                )
                
                if is_magic_basic_object
                    new_type.eigen = DefinedType.new(
                        path: "<Eigen:BasicObject>",
                        superclass: PendingDefinedType.new("Class"),
                        instance_methods: [
                            SpecialConstructorMethod.new(:new),
                        ],
                    )
                end

                # Find instance variable definitions
                node.comments
                    .select { |c| c.text.start_with?('#!var ') }
                    .each do |c|
                        unless /^#!var\s+(@[a-zA-Z_][a-zA-Z0-9_]*)\s+(.+)\s*$/ === c.text
                            Houndstooth::Errors::Error.new(
                                "Malformed #!var definition",
                                [[c.loc.expression, "invalid"]]
                            ).push
                            next 
                        end

                        var_name = $1
                        type = $2
                        
                        new_type.type_instance_variables[var_name] = TypeParser.parse_type(type)
                    end

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
                    node: node,
                    type_parameters: type_parameter_definitions(node),
                    path: append_type_and_rel_path(type_context, name),
                )
                new_type.eigen.superclass = PendingDefinedType.new("Module")
                environment.add_type(new_type)

                analyze(node: node.body, type_context: new_type)
            
            when Houndstooth::SemanticNode::MethodDefinition
                if node.target.nil?
                    target = type_context
                elsif node.target.is_a?(Houndstooth::SemanticNode::SelfKeyword)
                    target = type_context.eigen
                else
                    # TODO
                    Houndstooth::Errors::Error.new(
                        "`self` is the only supported explicit target",
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
                            type_parameters:
                                type_context.is_a?(DefinedType) \
                                    ? type_context.type_parameters
                                    : nil,
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

                # TODO: Don't allow methods with duplicate names
                target.instance_methods << Method.new(name, signatures)
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
                    node.name.to_s
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

        # Given a node, gets any type parameters defined on it.
        def type_parameter_definitions(node)
            node.comments
                .select { |c| c.text.start_with?('#!param ') }
                .map do |c|
                    unless /^#!param\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*$/ === c.text
                        Houndstooth::Errors::Error.new(
                            "Malformed #!param definition",
                            [[c.loc.expression, "invalid"]]
                        ).push
                        return 
                    end

                    $1
                end
        end
    end
end
