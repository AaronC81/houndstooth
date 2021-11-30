module TypeChecker::SemanticNode
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
                else
                    raise "unsupported argument type: #{arg}"
                end
            end

            parameters
        end


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
    end
end
