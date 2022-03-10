class Houndstooth::Environment
    class Type
        # Looks for methods on an instance of this type.
        # For example, you would resolve :+ on Integer, and :new on <Class:Integer>.
        #
        # @param [Symbol] method_name
        # @return [Method, nil]
        def resolve_instance_method(method_name, env, **_)
            nil
        end

        # Resolves the type of an instance variable by checking this type and its superclasses.
        # Returns nil if no type could be resolved.
        # @param [String] name
        # @return [Type, nil]
        def resolve_instance_variable(name)
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
        # based on the given instance, and if provided, the call-specific type arguments.
        #
        # The instance is required, but the call-specific type arguments are not, and should be
        # passed as `nil` for everything except methods.
        #
        # Because this has no link back the method type on which arguments are being substituted,
        # the caller must construct a hash of call-specific type arguments which includes their
        # name.
        #
        # The returned type could be a partial clone, deep clone, or even not a copy at all (just
        # `self`) - the implementor makes no guarantees. As such, do NOT modify the returned type.
        #
        # @param [TypeInstance] instance
        # @param [{String => Type}] call_type_args
        # @return [Type]
        def substitute_type_parameters(instance, call_type_args) = self

        # Returns an RBS representation of this type. Subclasses should override this.
        # This will not have the same formatting as the input string this is parsed from.
        def rbs
            "???"
        end 

        def instantiate(type_arguments = nil)
            TypeInstance.new(self, type_arguments: type_arguments || [])
        end
    end
end
