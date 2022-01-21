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

    def resolve_all_pending_types
        types.each do |_, type|
            type.resolve_all_pending_types(self)
        end
    end

    # Resolve a type by path; either an absolute path from the root namespace, or optionally as a
    # relative path from the context of it being used within the given type.
    # If the type does not exist, returns nil.
    #
    # @param [String] path The path to resolve. If `type_context` is nil, this is interpreted as an
    #   absolute path regardless of whether it is prefixed with `::`. If `type_context` is given,
    #   this is interpreted as a relative path without a `::` prefix, or an absolute path with one.
    # @param [DefinedType] type_context Optional: The context to search from.
    #
    # @return [DefinedType, nil]
    def resolve_type(path, type_context: nil)
        if path.start_with?('::') || type_context.nil?
            # Our `#types` field is indexed by absolute path, let's just look at that!
            # Prune the :: if present
            path = path[2..] if path.start_with?('::')
            return types[path]
        end
        
        # This is a relative path - split into parts
        path_parts = path.split('::')
        return nil if path_parts.empty?
        next_part, *rest_parts = *path_parts
    
        # Does the current type context contain the next part of the path?
        maybe_inner_type = types[type_context.path + '::' + next_part]
        if maybe_inner_type
            # Yes - either return if there's no more parts, or advance into that type and continue
            # the search
            if rest_parts.empty?
                maybe_inner_type
            else
                resolve_type(rest_parts.join('::'), type_context: maybe_inner_type)
            end
        else
            # No - check the current type context's parent
            # (Or, if there's no parent, we'll try searching for it as absolute as a last-ditch
            # attempt)
            if type_context.path.include?('::')
                resolve_type(path, type_context: types[type_context.path.split('::')[...-1].join('::')])
            else
                resolve_type(path, type_context: nil)
            end
        end
    end
end

require_relative 'environment/types'
require_relative 'environment/type_parser'
