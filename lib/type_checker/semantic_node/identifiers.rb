module TypeChecker::SemanticNode
    # A constant access, either with (`X::Y`) or without (`Y`) a leading target.
    class Constant < Base
        # @return [SemanticNode, nil]
        attr_accessor :target

        # @return [Symbol]
        attr_accessor :name

        register_ast_converter :const do |ast_node|
            target, name = *ast_node
            target = from_ast(target) if target

            Constant.new(
                ast_node: ast_node,
                target: target,
                name: name,
            )
        end
    end

    # A special node which is only valid as the target of a `Constant`. Represents the `::A` syntax
    # used to access a constant from the root namespace.
    class ConstantBase < Base
        register_ast_converter :cbase do |ast_node|
            ConstantBase.new(ast_node: ast_node)
        end 
    end

    # Assignment to a constant: `X::Y = 3`
    class ConstantAssignment < Base
        # @return [Constant, nil]
        attr_accessor :target

        # @return [Symbol]
        attr_accessor :name

        # @return [SemanticNode]
        attr_accessor :value

        register_ast_converter :casgn do |ast_node|
            target, name, value = *ast_node
            target = from_ast(target) if target
            value = from_ast(value)
            
            ConstantAssignment.new(
                ast_node: ast_node,
                target: target,
                name: name,
                value: value,
            )
        end
    end

    # A utility mixin to model variable accesses and assignments, since the code is shared between
    # local, instance, class, and global variables.
    #
    # This is not implemented as a class because an ambiguous `VariableAccess` would not be a valid
    # node - the kind of variable must always be known at parse-time.
    module VariableMixin
        def variable_mixin(type)
            # @return [Symbol]
            attr_accessor :name
            
            register_ast_converter type do |ast_node|
                self.new(ast_node: ast_node, name: ast_node.to_a.first)
            end
        end
    end

    # Represents a local variable. The parser looks at surrounding assignments and knows to generate
    # these instead of `Send`s in the correct places.
    class LocalVariable < Base
        extend VariableMixin
        variable_mixin :lvar

        # @return [Boolean]
        attr_accessor :fabricated
        alias fabricated? fabricated

        def self.fabricate
            @@fabricate_counter ||= 0
            @@fabricate_counter += 1

            name = "___fabricated_#{@@fabricate_counter}"
            LocalVariable.new(ast_node: nil, name: name, fabricated: true)
        end
    end

    # Represents an instance variable.
    class InstanceVariable < Base
        extend VariableMixin
        variable_mixin :ivar
    end

    # Represents a class variable.
    class ClassVariable < Base
        extend VariableMixin
        variable_mixin :cvar
    end

    # Represents a global variable.
    class GlobalVariable < Base
        extend VariableMixin
        variable_mixin :gvar
    end

    # Represents an assignment to a variable.
    class VariableAssignment < Base
        # @return [SemanticNode]
        attr_accessor :target

        # @return [SemanticNode]
        attr_accessor :value

        def self.from_ast_assignment(ast_node, variable_type, multiple_assignment_lhs: false, **_)
            name, value = *ast_node

            target = variable_type.new(
                ast_node: ast_node,
                name: name,
            )

            return target if multiple_assignment_lhs && value.nil?

            value = from_ast(value)

            VariableAssignment.new(
                ast_node: ast_node,
                target: target,
                value: value,
            )
        end

        register_ast_converter(:lvasgn) { |n, **o| from_ast_assignment(n, LocalVariable, **o)    }
        register_ast_converter(:ivasgn) { |n, **o| from_ast_assignment(n, InstanceVariable, **o) }
        register_ast_converter(:cvasgn) { |n, **o| from_ast_assignment(n, ClassVariable, **o)    }
        register_ast_converter(:gvasgn) { |n, **o| from_ast_assignment(n, GlobalVariable, **o)   }

        # Convert `x += 3` into `x = x + 3`
        register_ast_converter :op_asgn do |ast_node, **o|
            target, op, value = *ast_node

            # Get target as an e.g. LocalVariable
            target = from_ast(target, multiple_assignment_lhs: true)

            # TODO: No nice way of converting between =/non-= versions of method names currently
            # Also would need same considerations as noted for ||=/&&= to support
            raise "op-assign with Send LHS is not currently supported" if target.is_a?(Send)

            value = from_ast(value)

            VariableAssignment.new(
                ast_node: ast_node,
                target: target,
                value: Send.new(
                    # Yeah, this is the same as the parent, but there's not really a better option
                    ast_node: ast_node,

                    method: op,
                    target: target,

                    positional_arguments: [value]
                )
            )
        end
    end

    # An assignment to multiple variables at once, destructuring the right-hand-side across the
    # targets on the left-hand-side.
    #
    # A multiple assignment with one target is NOT the same as a single variable assignment!
    #
    #   a = [1, 2, 3]
    #   p a # => [1, 2, 3]
    #
    #   a, = [1, 2, 3]
    #   p a # => 1
    #
    class MultipleAssignment < Base
        # @return [<SemanticNode>]
        attr_accessor :targets

        # Yep, value singular - "a, b = 1, 2" is desugared by the parser to have an array as the RHS
        # @return [SemanticNode]
        attr_accessor :value

        register_ast_converter :masgn do |ast_node|
            lhs, rhs = *ast_node

            raise "unexpected left-hand-side of multiple assignment" unless lhs.type == :mlhs

            targets = lhs.to_a.map { |n| from_ast(n, multiple_assignment_lhs: true) }
            value = from_ast(rhs)
            
            MultipleAssignment.new(
                ast_node: ast_node,
                targets: targets,
                value: value,
            )
        end
    end

    # Represents a node which will be filled in magically by a parent node at code runtime, in cases
    # where complex runtime behaviour means that desugaring isn't possible at parse-time.
    #
    # Currently, this is only used where the left-hand-side of a multiple assignment will call a
    # method (with `Send`), e.g.:
    #
    #   self.a, self.b = *[1, 2]
    #  
    # This calls self.a=(1) and self.b=(2), but for other RHS values, we might not be able to 
    # determine what the parameters will be at parse-time. So, this parses as a multiple assignment
    # to targets (Send self.a=(MagicPlaceholder)) and (Send self.b=(MagicPlaceholder)).
    #
    # If you encounter this during node processing, something has probably gone wrong, and you 
    # should have processed the enclosing multiple assignment earlier!
    class MagicPlaceholder < Base
        def initialize(**kwargs)
            super(ast_node: nil, **kwargs)
        end
    end
end 
