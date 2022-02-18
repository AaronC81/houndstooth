class Houndstooth::Environment
    # A special type which can be used in place of a method, typically only `new`. Specifies
    # that the resolved instance method should actually be taken from an uneigened `initialize`.
    class SpecialConstructorMethod < Type
        def initialize(name)
            @name = name
        end

        attr_accessor :name

        def rbs
            "<special constructor '#{name}'>"
        end 
    end
end
