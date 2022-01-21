class TypeChecker::Environment
    class Type
        def resolve_all_pending_types(environment, context: nil); end

        # If the given type is an instance of `PendingDefinedType`, uses the given environment to
        # resolve the type. If the type couldn't be resolved, throws an exception.
        #
        # @param [Type] type
        # @param [Environment] environment
        # @return [DefinedType]
        def resolve_type_if_pending(type, context, environment)
            if type.is_a?(PendingDefinedType)
                new_type = environment.resolve_type(type.path, type_context: context)
                raise "could not resolve type '#{type.path}'" if new_type.nil? # TODO better error
                new_type
            else
                type.resolve_all_pending_types(environment, context: context)
                type
            end
        end
    end

    class PendingDefinedType < Type
        def initialize(path)
            @path = path
        end

        # @return [String]
        attr_reader :path
    end

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

        def resolve_all_pending_types(environment, context: nil)
            @superclass = resolve_type_if_pending(superclass, self, environment)
            @eigen = resolve_type_if_pending(eigen, self, environment)

            instance_methods.map do |method|
                method.resolve_all_pending_types(environment, context: self)
            end
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

        def resolve_all_pending_types(environment, context:)
            signatures.map do |sig|
                sig.resolve_all_pending_types(environment, context: context)
            end
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

        def resolve_all_pending_types(environment, context:)
            @return_type = resolve_type_if_pending(return_type, context, environment)
            
            positional_parameters.map do |param|
                param.resolve_all_pending_types(environment, context: context)
            end
            
            keyword_parameters.map do |param|
                param.resolve_all_pending_types(environment, context: context)
            end
            
            rest_positional_parameter&.resolve_all_pending_types(environment, context: context)
            rest_keyword_parameter&.resolve_all_pending_types(environment, context: context)
            block_parameter&.resolve_all_pending_types(environment, context: context)
        end
    end

    class Parameter < Type
        # Note: Parameters aren't *really* a type, but we need `resolve_type_if_pending`

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

        def resolve_all_pending_types(environment, context:)
            @type = resolve_type_if_pending(type, context, environment)
        end
    end

    class PositionalParameter < Parameter; end
    class KeywordParameter < Parameter; end
    class BlockParameter < Parameter; end
end
