class TypeChecker::Environment
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

require_relative 'environment/types'
require_relative 'environment/type_parser'
