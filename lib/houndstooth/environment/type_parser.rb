require 'rbs'

class Houndstooth::Environment
    module TypeParser
        # Parses an RBS type signature, e.g. "(String) -> Integer", and returns it as a `Type` in 
        # this project's type model.
        #
        # The types used do not necessarily need to be defined - all type references in the
        # returned signature will be instances of `PendingDefinedType`, which can be converted to
        # `DefinedType` using `Type#resolve_all_pending_types`.
        #
        # @param [String] input
        # @return [Type]
        def self.parse_method_type(input, method_definition_parameters: nil)
            types_from_rbs(
                RBS::Parser.parse_method_type(input),
                method_definition_parameters: method_definition_parameters
            )
        end

        # Converts an RBS type to this project's type model.
        def self.types_from_rbs(rbs_type, method_definition_parameters: nil)
            case rbs_type

            when RBS::MethodType, RBS::Types::Function
                conv = ->(klass, name, rbs, opt) do
                    klass.new(name, types_from_rbs(rbs.type), optional: opt)
                end

                # `MethodType` has a `Function` instance in its #type field
                # It also has a block, whereas `Function` does not
                if rbs_type.is_a?(RBS::MethodType)
                    # Get block parameter
                    block_parameter = rbs_type.block&.then { |bp| conv.(BlockParameter, nil, bp, !bp.required) }

                    # Replace `rbs_type` used throughout this method with the inner `Function`
                    rbs_type = rbs_type.type
                else
                    block_parameter = nil
                end 
                
                # Build up lists of positional and keyword parameters
                positional_parameters =
                    rbs_type.required_positionals.map { |rp| conv.(PositionalParameter, rp.name, rp, false) } \
                    + rbs_type.optional_positionals.map { |op| conv.(PositionalParameter, op.name, op, true) }

                keyword_parameters =
                    rbs_type.required_keywords.map { |n, rk| conv.(KeywordParameter, n, rk, false) } \
                    + rbs_type.optional_keywords.map { |n, ok| conv.(KeywordParameter, n, ok, true) }

                # Get rest parameters
                rest_positional_parameter = rbs_type.rest_positionals&.then { |rsp| conv.(PositionalParameter, rsp.name, rsp, false) }
                rest_keyword_parameter = rbs_type.rest_keywords&.then { |rsk| conv.(KeywordParameter, rsk.name, rsk, false) }

                # Get return type
                return_type = types_from_rbs(rbs_type.return_type)

                # TODO: If method definition parameter list given, check that the counts and names
                # line up (or fill in the names if the definition doesn't have them)

                MethodType.new(
                    positional: positional_parameters,
                    keyword: keyword_parameters,
                    rest_positional: rest_positional_parameter,
                    rest_keyword: rest_keyword_parameter,
                    block: block_parameter,
                    return_type: return_type
                )

            when RBS::Types::ClassInstance
                # rbs_type.name is not a String, it's a RBS::TypeName which also has a #namespace
                # property
                # Just converting to a String with #to_s simplifies things, since it includes the
                # namespace for us
                PendingDefinedType.new(rbs_type.name.to_s)

            when RBS::Types::Bases::Void
                VoidType.new

            when RBS::Types::Bases::Self
                SelfType.new

            when RBS::Types::Bases::Instance
                InstanceType.new

            when RBS::Types::Bases::Any # written as `untyped`
                UntypedType.new

            else
                # TODO: handle errors like this better
                raise "RBS type construct #{rbs_type.class} is not supported (usage: #{rbs_type.location.source})"
            end
        end
    end
end
