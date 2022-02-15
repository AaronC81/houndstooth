module Houndstooth::SemanticNode
    # A set of parameters accepted by a method definition or block.
    class Parameters < Base
        register_ast_converter :args do |ast_node|
            parameters = Parameters.new(
                ast_node: ast_node,
                positional_parameters: [],
                optional_parameters: [],
                keyword_parameters: [],
                optional_keyword_parameters: [],
                rest_parameter: nil,
                rest_keyword_parameter: nil,
                block_parameter: nil,
                only_proc_parameter: false,
                has_forward_parameter: false,
            )

            ast_node.to_a.each do |arg|
                case arg.type
                when :arg
                    parameters.positional_parameters << arg.to_a.first
                when :kwarg
                    parameters.keyword_parameters << arg.to_a.first
                when :optarg
                    name, value = *arg
                    parameters.optional_parameters << [name, from_ast(value)]
                when :kwoptarg
                    name, value = *arg
                    parameters.optional_keyword_parameters << [name, from_ast(value)]
                when :restarg
                    parameters.rest_parameter = arg.to_a.first
                when :kwrestarg
                    parameters.rest_keyword_parameter = arg.to_a.first 
                when :procarg0
                    parameters.only_proc_parameter = true
                when :blockarg
                    parameters.block_parameter = arg.to_a.first
                when :forward_arg
                    parameters.has_forward_parameter = true
                else
                    Houndstooth::Errors::Error.new(
                        "Unsupported argument type",
                        [[arg.loc.expression, "unsupported"]]
                    ).push
                    next nil
                end
            end

            parameters
        end

        # True if this block of parameters takes the magic "progarc0", which in blocks can represent
        # all parameters given in an array.
        # @return [Boolean]
        attr_accessor :only_proc_parameter

        # @return [<Symbol>]
        attr_accessor :positional_parameters
        
        # @return [<(Symbol, SemanticNode)>]
        attr_accessor :optional_parameters
        
        # @return [<Symbol>]
        attr_accessor :keyword_parameters
        
        # @return [<(Symbol, SemanticNode)>]
        attr_accessor :optional_keyword_parameters

        # @return [Symbol, nil]
        attr_accessor :rest_parameter

        # @return [Symbol, nil]
        attr_accessor :rest_keyword_parameter

        # @return [Symbol, nil]
        attr_accessor :block_parameter

        # True if this method has a `...` parameter.
        # @return [Boolean]
        attr_accessor :has_forward_parameter

        def add_to_instruction_block(block)
            if optional_parameters.any? ||
                keyword_parameters.any? ||
                optional_keyword_parameters.any? ||
                rest_parameter ||
                rest_keyword_parameter ||
                has_forward_parameter ||
                block_parameter ||
                only_proc_parameter

                # Replace call with a nil
                Houndstooth::Errors::Error.new(
                    "Only required positional parameters are supported",
                    [[ast_node.loc.expression, "unsupported parameters in block"]]
                ).push 
                return false
            end

            # Create parameters on this block
            positional_parameters.each do |name|
                block.parameters << I::Variable.new(name.to_s)
            end

            return true
        end
    end
end
