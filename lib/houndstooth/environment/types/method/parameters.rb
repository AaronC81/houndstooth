class Houndstooth::Environment
    class Parameter < Type
        # Note: Parameters aren't *really* a type, but we need `resolve_type_if_pending`

        # @return [Name]
        attr_reader :name

        # @return [Type]
        attr_accessor :type

        # @return [Boolean]
        attr_reader :optional
        alias optional? optional

        def initialize(name, type, optional: false)
            @name = name
            @type = type
            @optional = optional
        end

        def resolve_all_pending_types(environment, context:)
            @type = resolve_type_if_pending(type, context, environment)
        end

        def substitute_type_parameters(instance)
            clone.tap do |t|
                t.type = t.type.substitute_type_parameters(instance)
            end
        end
    end

    class PositionalParameter < Parameter
        def rbs
            if name
                "#{optional? ? '?' : ''}#{type.rbs} #{name}"
            else
                "#{optional? ? '?' : ''}#{type.rbs}"
            end
        end
    end

    class KeywordParameter < Parameter
        def rbs
            "#{optional? ? '?' : ''}#{name}: #{type.rbs}"
        end
    end

    class BlockParameter < Parameter
        def rbs
            "#{optional? ? '?' : ''}{ #{type.rbs} }"
        end
    end
end
