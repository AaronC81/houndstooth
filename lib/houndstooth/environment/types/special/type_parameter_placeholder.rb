class Houndstooth::Environment
    # A type which will be replaced by a type argument later.
    class TypeParameterPlaceholder < Type
        def initialize(name)
            @name = name
        end

        attr_accessor :name

        def accepts?(other)
            if other.is_a?(TypeParameterPlaceholder) && name == other.name
                1
            else
                false
            end
        end

        def rbs
            name
        end

        def substitute_type_parameters(instance, call_type_args)
            # Call type arguments take priority, check those first
            return call_type_args[name] if call_type_args[name]

            # Get index of type parameter
            index = instance.type.type_parameters.index { |tp| tp == name } or return self

            # Replace with type argument, which should be an instance
            instance.type_arguments[index] or self
        end

        # Yikes!
        # It doesn't ever make sense to instantiate a type parameter, and trying to do so was
        # causing problems when passing type arguments around functions, so just don't allow it
        def instantiate(...) = self
    end
end
