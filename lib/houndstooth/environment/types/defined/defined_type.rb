class Houndstooth::Environment
    class DefinedType < Type
        def initialize(path: nil, node: nil, superclass: nil, instance_methods: nil, eigen: :generate, type_parameters: nil)
            @path = path.to_s
            @node = node
            @superclass = superclass
            @instance_methods = instance_methods || []
            @type_parameters = type_parameters || []
            @type_instance_variables = {}

            if eigen == :generate
                @eigen = DefinedType.new(
                    path: "<Eigen:#{path}>",
                    superclass:
                        if superclass.is_a?(PendingDefinedType)
                            PendingDefinedType.new("<Eigen:#{superclass.path}>")
                        else 
                            superclass&.eigen
                        end,
                    eigen: nil,
                )
            else
                @eigen = eigen
            end
        end

        def instantiate(type_arguments = nil)
            TypeInstance.new(self, type_arguments: type_arguments || [])
        end

        # @return [String]
        attr_reader :path

        # @return [String]
        def name
            path.split("::").last
        end

        # @return [SemanticNode]
        attr_reader :node

        # @return [Type, nil]
        attr_accessor :superclass

        # @return [Type]
        attr_accessor :eigen

        # @return [<Method>]
        attr_reader :instance_methods

        # @return [<String>]
        attr_reader :type_parameters

        # @return [{String => Type}]
        attr_reader :type_instance_variables

        def resolve_instance_method(method_name, env, instance: nil, top_level: true)            
            # Is it available on this type?
            # If not, check the superclass
            # If there's no superclass, then there is no method to be found, so return nil
            instance_method = instance_methods.find { _1.name == method_name }

            found = if instance_method
                instance_method
            else
                superclass&.resolve_instance_method(method_name, env, instance: instance, top_level: false)
            end

            # If the upper chain returned a special constructor method, we need to convert this by
            # grabbing our instance's `initialize` type
            if top_level && found && found.is_a?(SpecialConstructorMethod)
                initialize_sig = env.resolve_type(uneigen).resolve_instance_method(:initialize, env, instance: instance)
                Method.new(
                    :new,
                    initialize_sig.signatures.map do |sig|
                        # Same parameters, but returns `instance`
                        new_sig = sig.clone
                        new_sig.return_type = InstanceType.new
                        new_sig
                    end,
                    const: initialize_sig.const,
                )
            else
                found
            end
        end

        def resolve_instance_variable(name)
            var_here = type_instance_variables[name]
            return var_here if var_here

            superclass&.resolve_instance_variable(name)
        end

        # A path to this type, but with one layer of "eigen-ness" removed from the final element.
        # A bit cursed, but used for constant resolution.
        # @return [String]
        def uneigen
            path_parts = path.split("::")
            *rest, name = path_parts

            raise "internal error: can't uneigen a non-eigen type" unless /^<Eigen:(.+)>$/ === name
            uneigened_name = $1

            [*rest, uneigened_name].join("::")
        end

        def resolve_all_pending_types(environment, context: nil)
            @superclass = resolve_type_if_pending(superclass, self, environment)
            @eigen = resolve_type_if_pending(eigen, self, environment)

            instance_methods.map do |method|
                method.resolve_all_pending_types(environment, context: self)
            end

            type_instance_variables.keys.each do |k|
                type_instance_variables[k] = resolve_type_if_pending(type_instance_variables[k], self, environment)
            end
        end

        def accepts?(other)
            return false unless other.is_a?(DefinedType)
            
            distance = 0
            current = other
            until current.nil?
                return distance if current == self

                current = current&.superclass
                distance += 1
            end

            false
        end

        def rbs
            path
        end
    end
end
