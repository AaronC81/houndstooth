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

        def self.from_ast_assignment(ast_node, variable_type)
            name, value = *ast_node

            value = from_ast(value)
            target = variable_type.new(
                ast_node: ast_node,
                name: name,
            )

            VariableAssignment.new(
                ast_node: ast_node,
                target: target,
                value: value,
            )
        end

        register_ast_converter(:lvasgn) { |n| from_ast_assignment(n, LocalVariable)    }
        register_ast_converter(:ivasgn) { |n| from_ast_assignment(n, InstanceVariable) }
        register_ast_converter(:cvasgn) { |n| from_ast_assignment(n, ClassVariable)    }
        register_ast_converter(:gvasgn) { |n| from_ast_assignment(n, GlobalVariable)   }
    end
end 
