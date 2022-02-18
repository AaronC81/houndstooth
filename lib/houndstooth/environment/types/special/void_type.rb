class Houndstooth::Environment
    class VoidType < Type
        def accepts?(other)
            # Only valid as a return type, and you can return anything in a void method
            1
        end

        def rbs
            "void"
        end
    end
end
