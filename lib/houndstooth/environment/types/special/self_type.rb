class Houndstooth::Environment
    class SelfType < Type
        # TODO: implement accepts?

        def rbs
            "self"
        end
    end
end
