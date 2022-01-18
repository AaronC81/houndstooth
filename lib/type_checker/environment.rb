class TypeChecker::Environment
    class Type; end

    class DefinedType < Type
        def initialize(path: nil, definition_loc: nil, superclass: nil, instance_methods: nil, static_methods: nil, eigen: :generate)
            @path = path
            @definition_loc = definition_loc
            @superclass = superclass
            @instance_methods = instance_methods || []
            @static_methods = static_methods || []

            if eigen == :generate
                @eigen = DefinedType.new(
                    path: "<Eigen:#{path}>",
                    superclass: superclass&.eigen,
                    eigen: nil,
                )
            else
                @eigen = eigen
            end
        end

        # @return [String]
        attr_reader :path

        # @return [String]
        def name
            path.split("::").last
        end

        # @return [Parser::Source::Range]
        attr_reader :definition_loc

        # @return [Type, nil]
        attr_accessor :superclass

        # @return [Type]
        attr_reader :eigen

        # @return [<Method>]
        attr_reader :instance_methods

        # Looks for methods on an instance of this type.
        # For example, you would resolve :+ on Integer, and :new on <Class:Integer>.
        #
        # @param [Symbol] method_name
        # @return [Method, nil]
        def resolve_instance_method(method_name)
            # Is it available on this type?
            instance_method = instance_methods.find { _1.name == method_name }
            return instance_method if instance_method

            # If not, check the superclass
            # If there's no superclass, then there is no method to be found, so return nil
            superclass&.resolve_instance_method(method_name)
        end
    end
    
    class SelfType < Type; end
    class VoidType < Type; end
    class UntypedType < Type; end

    class Method
        # @return [String]
        attr_reader :name

        # @return [<MethodType>]
        attr_reader :signatures

        # :public, :protected or :private
        # @return [Symbol]
        attr_reader :visibility

        # @return [Boolean]
        attr_reader :const
        alias const? const

        def initialize(name, signatures = nil, visibility: :public, const: false)
            @name = name
            @signatures = signatures || []
            @visibility = visibility
            @const = const
        end
    end

    class MethodType < Type
        # @return [<PositionalParameter>]
        attr_reader :positional_parameters

        # @return [<KeywordParameter>]
        attr_reader :keyword_parameters

        # @return [PositionalParameter, nil]
        attr_reader :rest_positional_parameter

        # @return [KeywordParameter, nil]
        attr_reader :rest_keyword_parameter

        # @return [BlockParameter, nil]
        attr_reader :block_parameter

        # @return [Type]
        attr_reader :return_type

        def initialize(positional: [], keyword: [], rest_positional: nil, rest_keyword: nil, block: nil, return_type: nil)
            super()

            @positional_parameters = positional
            @keyword_parameters = keyword
            @rest_positional_parameter = rest_positional
            @rest_keyword_parameter = rest_keyword
            @block_parameter = block
            @return_type = return_type || VoidType.new
        end
    end

    class Parameter
        # @return [Name]
        attr_reader :name

        # @return [Type]
        attr_reader :type

        # @return [Boolean]
        attr_reader :optional
        alias optional? optional

        def initialize(name, type, optional: false)
            @name = name
            @type = type
            @optional = optional
        end
    end

    class PositionalParameter < Parameter; end
    class KeywordParameter < Parameter; end
    class BlockParameter < Parameter; end

    def initialize
        @types = {}
    end

    def add_type(type)
        # Add the type and its entire eigen chain
        @types[type.path] = type
        add_type(type.eigen) if type.eigen
    end

    # @return [{String, DefinedType}] 
    attr_reader :types
end
