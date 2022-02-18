class Houndstooth::Environment
    # A slightly hacky type which represents the base namespace, such as when a constant is accessed
    # using ::A syntax. 
    # This only appears in one place; the type change of a `ConstantBaseAccessInstruction`. This is
    # invalid if it appears in any context where an actual type is expected.
    # Unlike other constant accesses, this does NOT represent an *instance* of the base namespace,
    # because that cannot exist.
    class BaseDefinedType < Type
        def accepts?(other)
            false
        end

        def name
            ""
        end
        alias path name
        alias uneigen name

        def rbs
            "(base)"
        end 
    end
end
