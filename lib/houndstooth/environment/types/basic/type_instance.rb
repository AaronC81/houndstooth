class Houndstooth::Environment
    # Represents type arguments passed with a usage of a type. This doesn't necessarily need to be
    # an "instance" of a class - "instance" refers to a usage of a type.
    class TypeInstance < Type
        def initialize(type, type_arguments: nil)
            @type = type
            @type_arguments = type_arguments || []
        end

        # @return [DefinedType]
        attr_accessor :type

        # @return [<Type>]
        attr_accessor :type_arguments

        def ==(other)
            other.is_a?(TypeInstance) \
                && type == other.type \
                && type_arguments == other.type_arguments
        end

        def hash = [type, type_arguments].hash

        def accepts?(other)
            return false unless other.is_a?(TypeInstance)

            type.accepts?(other.type)
        end

        def resolve_instance_method(method_name, env, top_level: true)
            type.resolve_instance_method(method_name, env, instance: self, top_level: top_level)
        end

        def resolve_all_pending_types(environment, context: nil)
            @type = resolve_type_if_pending(type, context, environment)
            type_arguments.map! { |type| resolve_type_if_pending(type, context, environment) }
        end

        def substitute_type_parameters(instance)
            clone.tap do |t|
                t.type = t.type.substitute_type_parameters(instance)
                t.type_arguments = t.type_arguments.map { |arg| arg.substitute_type_parameters(instance) }
            end
        end

        def rbs
            if type_arguments.any?
                "#{type.rbs}[#{type_arguments.map(&:rbs).join(', ')}]"
            else
                type.rbs
            end 
        end
    end
end
