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
    end
end
