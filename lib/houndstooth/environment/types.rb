class Houndstooth::Environment
    class Type
        # Looks for methods on an instance of this type.
        # For example, you would resolve :+ on Integer, and :new on <Class:Integer>.
        #
        # @param [Symbol] method_name
        # @return [Method, nil]
        def resolve_instance_method(method_name)
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

        # Returns an RBS representation of this type. Subclasses should override this.
        # This will not have the same formatting as the input string this is parsed from.
        # TODO: implement for method types
        def rbs
            "???"
        end 
    end

    class PendingDefinedType < Type
        def initialize(path)
            @path = path
        end

        # @return [String]
        attr_reader :path

        def rbs
            "#{path} (unresolved)"
        end 
    end

    class DefinedType < Type
        def initialize(path: nil, node: nil, superclass: nil, instance_methods: nil, eigen: :generate)
            @path = path.to_s
            @node = node
            @superclass = superclass
            @instance_methods = instance_methods || []

            if eigen == :generate
                @eigen = DefinedType.new(
                    path: "<Eigen:#{path}>",
                    superclass:
                        if superclass.is_a?(PendingDefinedType)
                            PendingDefinedType.new("<Eigen:#{superclass.path}>")
                        else 
                            superclass&.eigen
                        end,
                    eigen: nil,
                )
            else
                @eigen = eigen
            end
        end

        # @return [String]
        attr_reader :path

        # @return [String]
        def name
            path.split("::").last
        end

        # @return [SemanticNode]
        attr_reader :node

        # @return [Type, nil]
        attr_accessor :superclass

        # @return [Type]
        attr_accessor :eigen

        # @return [<Method>]
        attr_reader :instance_methods

        def resolve_instance_method(method_name)
            # Is it available on this type?
            instance_method = instance_methods.find { _1.name == method_name }
            return instance_method if instance_method

            # If not, check the superclass
            # If there's no superclass, then there is no method to be found, so return nil
            superclass&.resolve_instance_method(method_name)
        end

        # A path to this type, but with one layer of "eigen-ness" removed from the final element.
        # A bit cursed, but used for constant resolution.
        # @return [String]
        def uneigen
            path_parts = path.split("::")
            *rest, name = path_parts

            raise "internal error: can't uneigen a non-eigen type" unless /^<Eigen:(.+)>$/ === name
            uneigened_name = $1

            [*rest, uneigened_name].join("::")
        end

        def resolve_all_pending_types(environment, context: nil)
            @superclass = resolve_type_if_pending(superclass, self, environment)
            @eigen = resolve_type_if_pending(eigen, self, environment)

            instance_methods.map do |method|
                method.resolve_all_pending_types(environment, context: self)
            end
        end

        def accepts?(other)
            return false unless other.is_a?(DefinedType)
            
            distance = 0
            current = other
            until current.nil?
                return distance if current == self

                current = current&.superclass
                distance += 1
            end

            false
        end

        def rbs
            path
        end
    end

    # A slightly hacky type which represents the base namespace, such as when a constant is accessed
    # using ::A syntax. 
    # This only appears in one place; the type change of a `ConstantBaseAccessInstruction`. This is
    # invalid if it appears in any context where an actual type is expected.
    # Unlike other constant accesses, this does NOT represent an *instance* of the base namespace,
    # because that cannot exist.
    class BaseDefinedType < Type
        def accepts?(other)
            false
        end

        def name
            ""
        end
        alias path name
        alias uneigen name

        def rbs
            "(base)"
        end 
    end

    class UnionType < Type
        # The types which this union is made up of.
        # @return [<Type>]
        attr_accessor :types

        def initialize(types)
            @types = types
        end

        # Simplifies this union using a couple of different strategies:
        #   - If any of the child types is also a `UnionType`, flattens it into one longer union.
        #   - If some children are the same, combines them.
        #   - If there is only one child, returns the child.
        # Returns a new type with the same references, since the latter step could return something
        # other than `UnionType`.
        def simplify
            new_types = types.flat_map do |type|
                if type.is_a?(UnionType)
                    type.types
                else
                    [type]
                end
            end

            new_types.uniq!

            if new_types.length == 1
                new_types.first
            else
                UnionType.new(new_types)
            end
        end

        def resolve_all_pending_types(environment, context: nil)
            types.map! { |type| resolve_type_if_pending(type, self, environment) }
        end

        def accepts?(other)
            # Normalise into an array
            if other.is_a?(UnionType)
                other_types = other.types
            else
                other_types = [other]
            end

            # Each of the other types should fit into one of this type's options
            # Find minimum distances from each candidate and sum them, plus one since this union is
            # itself a "hop"
            other_types.map do |ot|
                candidates = types.map { |mt| mt.accepts?(ot) }.reject { |r| r == false }
                return false if candidates.empty?

                candidates.min
            end.sum + 1
        end

        def rbs
            types.map(&:rbs).join(" | ")
        end 
    end
    
    class SelfType < Type
        # TODO: implement accepts?

        def rbs
            "self"
        end
    end

    class InstanceType < Type
        # TODO: implement accepts?

        def rbs
            "instance"
        end
    end

    class VoidType < Type
        def accepts?(other)
            # Only valid as a return type, and you can return anything in a void method
            1
        end

        def rbs
            "void"
        end
    end

    class UntypedType < Type
        def accepts?(other)
            1
        end

        def rbs
            "untyped"
        end
    end

    class Method
        # @return [String]
        attr_reader :name

        # @return [<MethodType>]
        attr_reader :signatures

        # :public, :protected or :private
        # @return [Symbol]
        attr_reader :visibility

        # @return [Boolean]
        attr_reader :const
        alias const? const

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

        # Given a set of arguments and their types, resolves and returns the best matching signature
        # of this method.
        #
        # If multiple signatures match, the "best" is chosen according to the distance rules used
        # by `Type#accepts?` - the type with the lowest distance over all arguments is returned.
        # If no signatures match, returns nil.
        #
        # @param [<(Instructions::Argument, Type)>] arguments
        # @return [MethodType, nil]
        def resolve_matching_signature(arguments)            
            sigs_with_scores = signatures
                .map { |sig| [sig, sig.accepts_arguments?(arguments)] }
                .reject { |_, r| r == false }

            if sigs_with_scores.any?
                sigs_with_scores.min_by { |sig, score| score }[0]
            else
                nil
            end
        end
    end

    class MethodType < Type
        # @return [<PositionalParameter>]
        attr_reader :positional_parameters

        # @return [<KeywordParameter>]
        attr_reader :keyword_parameters

        # @return [PositionalParameter, nil]
        attr_reader :rest_positional_parameter

        # @return [KeywordParameter, nil]
        attr_reader :rest_keyword_parameter

        # @return [BlockParameter, nil]
        attr_reader :block_parameter

        # @return [Type]
        attr_reader :return_type

        def initialize(positional: [], keyword: [], rest_positional: nil, rest_keyword: nil, block: nil, return_type: nil)
            super()

            @positional_parameters = positional
            @keyword_parameters = keyword
            @rest_positional_parameter = rest_positional
            @rest_keyword_parameter = rest_keyword
            @block_parameter = block
            @return_type = return_type || VoidType.new
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

        # TODO: implement accepts?

        def rbs
            params = 
                [positional_parameters.map(&:rbs), keyword_parameters.map(&:rbs)].flatten.join(", ")
                
            "(#{params}) #{block_parameter ? "#{block_parameter.rbs} " : ''}-> #{return_type.rbs}"
        end
    end

    class Parameter < Type
        # Note: Parameters aren't *really* a type, but we need `resolve_type_if_pending`

        # @return [Name]
        attr_reader :name

        # @return [Type]
        attr_reader :type

        # @return [Boolean]
        attr_reader :optional
        alias optional? optional

        def initialize(name, type, optional: false)
            @name = name
            @type = type
            @optional = optional
        end

        def resolve_all_pending_types(environment, context:)
            @type = resolve_type_if_pending(type, context, environment)
        end
    end

    class PositionalParameter < Parameter
        def rbs
            if name
                "#{optional? ? '?' : ''}#{type.rbs} #{name}"
            else
                "#{optional? ? '?' : ''}#{type.rbs}"
            end
        end
    end

    class KeywordParameter < Parameter
        def rbs
            "#{optional? ? '?' : ''}#{name}: #{type.rbs}"
        end
    end

    class BlockParameter < Parameter
        def rbs
            "#{optional? ? '?' : ''}{ #{type.rbs} }"
        end
    end
end
