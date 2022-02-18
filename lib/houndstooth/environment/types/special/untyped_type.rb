class Houndstooth::Environment
    class UntypedType < Type
        def accepts?(other)
            1
        end

        def rbs
            "untyped"
        end
    end
end
