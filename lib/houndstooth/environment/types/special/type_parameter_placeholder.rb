class Houndstooth::Environment
    # A type which will be replaced by a type argument later.
    class TypeParameterPlaceholder < Type
        def initialize(name)
            @name = name
        end

        attr_accessor :name

        def accepts?(other)
            other.is_a?(TypeParameterPlaceholder) && name == other.name
        end

        def rbs
            name
        end

        def substitute_type_parameters(instance)
            # Get index of type parameter
            index = instance.type.type_parameters.index { |tp| tp == name } \
                or raise "internal error: somehow no type parameter named #{name}"

            # Replace with type argument, which should be an instance
            instance.type_arguments[index] \
                or raise "internal error: somehow no type argument for parameter #{name} (index #{index}), this should've been checked earlier!"        
        end
    end
end
