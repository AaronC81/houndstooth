class Houndstooth::Environment
    class Type
        # Looks for methods on an instance of this type.
        # For example, you would resolve :+ on Integer, and :new on <Class:Integer>.
        #
        # @param [Symbol] method_name
        # @return [Method, nil]
        def resolve_instance_method(method_name, env)
            nil
        end

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
                # Do not recurse into DefinedTypes, this could cause infinite loops if classes are
                # superclasses of each other
                if !type.is_a?(DefinedType)
                    type&.resolve_all_pending_types(environment, context: context)
                end
                type
            end
        end

        # Determine whether the type `other` can be passed into a "slot" (e.g. function parameter)
        # which takes this type.
        #
        # The return value is either:
        #   - A positive (or zero) integer, indicating the "distance" between the two types. Zero
        #     indicates an exact type match (e.g. Integer and Integer), while every increment 
        #     indicates a level of cast (e.g. Integer -> Numeric = 1, Integer -> Object = 2).
        #     This can be used to select an overload which is closest to the given set of arguments
        #     if multiple overloads match.
        #   - False, if the types do not match.
        def accepts?(other)
            raise "unimplemented for #{self.class.name}"
        end

        # Returns a copy of this type with any type parameters substituted for their actual values
        # based on the given instance.
        #
        # The returned type could be a partial clone, deep clone, or even not a copy at all (just
        # `self`) - the implementor makes no guarantees. As such, do NOT modify the returned type.
        #
        # @param [TypeInstance] instance
        # @return [Type]
        def substitute_type_parameters(instance) = self

        # Returns an RBS representation of this type. Subclasses should override this.
        # This will not have the same formatting as the input string this is parsed from.
        # TODO: implement for method types
        def rbs
            "???"
        end 
    end
end
