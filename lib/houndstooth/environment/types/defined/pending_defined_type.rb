class Houndstooth::Environment
    class PendingDefinedType < Type
        def initialize(path)
            @path = path
        end

        # @return [String]
        attr_reader :path

        def rbs
            "#{path} (unresolved)"
        end 
    end
end
