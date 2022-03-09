class Houndstooth::Environment
    class MethodType < Type
        # @return [<PositionalParameter>]
        attr_accessor :positional_parameters

        # @return [<KeywordParameter>]
        attr_accessor :keyword_parameters

        # @return [PositionalParameter, nil]
        attr_accessor :rest_positional_parameter

        # @return [KeywordParameter, nil]
        attr_accessor :rest_keyword_parameter

        # @return [BlockParameter, nil]
        attr_accessor :block_parameter

        # @return [Type]
        attr_accessor :return_type

        # @return [<String>]
        attr_accessor :type_parameters

        def initialize(positional: [], keyword: [], rest_positional: nil, rest_keyword: nil, block: nil, return_type: nil, type_parameters: nil)
            super()

            @positional_parameters = positional
            @keyword_parameters = keyword
            @rest_positional_parameter = rest_positional
            @rest_keyword_parameter = rest_keyword
            @block_parameter = block
            @return_type = return_type || VoidType.new
            @type_parameters = type_parameters || []
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

        # Determines whether this method can be called with the given arguments and their types.
        # Follows the same return-value rules as `accepts?`.
        #
        # @param [<(Instructions::Argument, Type)>] arguments
        # @return [Integer, Boolean]
        def accepts_arguments?(arguments)
            distance_total = 0
            args_index = 0

            # Check the positional parameters first
            positional_parameters.each do |param|
                # Is there also a positional argument in this index slot?
                this_arg, this_type = arguments[args_index]
                if this_arg.is_a?(Houndstooth::Instructions::PositionalArgument)
                    # Yes, so this argument was definitely passed to this parameter
                    # Are the types compatible?
                    dist = param.type.accepts?(this_type)
                    if dist
                        # Yep! All is well. Add to total distance
                        distance_total += dist
                        args_index += 1
                    else
                        # Nope, this isn't valid. Bail
                        return false
                    end
                else
                    # No positional argument - but that's OK if this parameter is optional
                    if !param.optional?
                        # Missing argument not allowed
                        return false
                    end
                end
            end

            # Are there any positional arguments left over?
            while arguments[args_index] && arguments[args_index][0].is_a?(Houndstooth::Instructions::PositionalArgument)
                this_arg, this_type = arguments[args_index]

                # Is there a rest-parameter to take these?
                if !rest_positional_parameter.nil?
                    # Yep, but does this argument match the type of the rest positional?
                    dist = param.type.accepts?(this_type)
                    if dist
                        # Correct - this is passed into the splat!
                        distance_total += dist
                        args_index += 1
                    else
                        # Not the right type for the splat, invalid
                        return false
                    end
                else
                    # No, error - too many arguments
                    return false
                end
            end

            # TODO: keyword arguments
            raise "keyword argument checking not implemeneted" \
                if arguments.find { |x, _| x.is_a?(Houndstooth::Instructions::KeywordArgument) }

            distance_total
        end

        def substitute_type_parameters(instance)
            clone.tap do |t|
                t.positional_parameters = t.positional_parameters.map { |p| p.substitute_type_parameters(instance) }
                t.keyword_parameters = t.keyword_parameters.map { |p| p.substitute_type_parameters(instance) }

                t.rest_positional_parameter = t.rest_positional_parameter&.substitute_type_parameters(instance)
                t.rest_keyword_parameter = t.rest_keyword_parameter&.substitute_type_parameters(instance)
                t.block_parameter = t.block_parameter&.substitute_type_parameters(instance)

                t.return_type = t.return_type.substitute_type_parameters(instance)
            end
        end

        # TODO: implement accepts?

        def rbs
            params = 
                [positional_parameters.map(&:rbs), keyword_parameters.map(&:rbs)].flatten.join(", ")
                
            "(#{params}) #{block_parameter ? "#{block_parameter.rbs} " : ''}-> #{return_type.rbs}"
        end
    end
end
    