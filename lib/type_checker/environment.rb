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

    class Method
        # @return [String]
        attr_reader :name

        # :public, :protected or :private
        # @return [Symbol]
        attr_reader :visibility

        def initialize(name, visibility: :public)
            @name = name
            @visibility = visibility
        end

        # TODO: list of MethodSignature objects
    end

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
