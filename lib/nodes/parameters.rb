class Parameters < SemanticNode
    def initialize(**args)
        defaults = {
            positional_parameters: [],
            optional_parameters: [],
            keyword_parameters: [],
            optional_keyword_parameters: [],
            rest_parameter: nil,
            rest_keyword_parameter: nil,
        }

        super **defaults.merge(args)
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
