class Constant < SemanticNode
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

class ConstantBase < SemanticNode
    register_ast_converter :cbase do |ast_node|
        ConstantBase.new(ast_node: ast_node)
    end 
end

class ConstantAssignment < SemanticNode
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

module VariableMixin
    def variable_mixin(type)
        # @return [Symbol]
        attr_accessor :name
        
        register_ast_converter type do |ast_node|
            self.new(ast_node: ast_node, name: ast_node.to_a.first)
        end
    end

    def variable_assignment_mixin(type)
        # @return [Symbol]
        attr_accessor :name

        # @return [SemanticNode]
        attr_accessor :value

        register_ast_converter type do |ast_node|
            name, value = *ast_node
            value = from_ast(value)
            
            self.new(
                ast_node: ast_node,
                name: name,
                value: value,
            )
        end
    end
end

class LocalVariable < SemanticNode
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

class LocalVariableAssignment < SemanticNode
    extend VariableMixin
    variable_assignment_mixin :lvasgn
end

class InstanceVariable < SemanticNode
    extend VariableMixin
    variable_mixin :ivar
end

class InstanceVariableAssignment < SemanticNode
    extend VariableMixin
    variable_assignment_mixin :ivasgn
end

class ClassVariable < SemanticNode
    extend VariableMixin
    variable_mixin :cvar
end

class ClassVariableAssignment < SemanticNode
    extend VariableMixin
    variable_assignment_mixin :cvasgn
end

class GlobalVariable < SemanticNode
    extend VariableMixin
    variable_mixin :gvar
end

class GlobalVariableAssignment < SemanticNode
    extend VariableMixin
    variable_assignment_mixin :gvasgn
end

