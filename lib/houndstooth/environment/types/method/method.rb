class Houndstooth::Environment
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

        # Given a set of arguments and their types, resolves and returns the best matching signature
        # of this method.
        #
        # If multiple signatures match, the "best" is chosen according to the distance rules used
        # by `Type#accepts?` - the type with the lowest distance over all arguments is returned.
        # If no signatures match, returns nil.
        #
        # @param [TypeInstance] instance
        # @param [<(Instructions::Argument, Type)>] arguments
        # @return [MethodType, nil]
        def resolve_matching_signature(instance, arguments)            
            sigs_with_scores = signatures
                .map { |sig| [sig, sig.substitute_type_parameters(instance).accepts_arguments?(arguments)] }
                .reject { |_, r| r == false }

            if sigs_with_scores.any?
                sigs_with_scores.min_by { |sig, score| score }[0]
            else
                nil
            end
        end
    end
end
