class Houndstooth::Environment
    class Method
        # @return [String]
        attr_reader :name

        # @return [<MethodType>]
        attr_reader :signatures

        # :public, :protected or :private
        # @return [Symbol]
        attr_reader :visibility

        # If a symbol, the kind of constness this method has:
        #   - :normal, defined as user-specified source, can be used anywhere
        #   - :internal, defined in Houndstooth, can be used anywhere
        #   - :required, defined as user-specified source, can only be used from a const context
        #   - :required_internal, defined in Houndstooth, can only be used from a const context
        # If nil, this method is not const.
        # @return [Symbol, nil]
        attr_reader :const

        def const?; !const.nil?; end
        def const_internal?; const == :internal || const == :required_internal; end
        def const_required?; const == :required || const == :required_internal; end

        # The instruction block which implements this method.
        # @return [InstructionBlock]
        attr_accessor :instruction_block

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

        def substitute_type_parameters(instance)
            raise 'internal error: tried to substitute parameters on a Method; too high in the hierarchy for this to be sensible'
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
