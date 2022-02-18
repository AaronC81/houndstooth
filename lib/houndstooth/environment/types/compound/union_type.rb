class Houndstooth::Environment
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

            new_types.uniq! { |x| x.hash }

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
end
