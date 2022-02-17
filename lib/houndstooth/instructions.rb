module Houndstooth
    module Instructions
        # A variable. Every instruction assigns its results to a variable.
        # This does NOT necessarily correlate to a Ruby variable - these variables are temporary,
        # and only created to "simplify" Ruby code. For example, "2 + 6" would become:
        #   $1 = 2
        #   $2 = 6
        #   $3 = $1 + $2
        # $1, $2 and $3 are variables.
        class Variable
            # The globally unique ID of this variable.
            # @return [Integer]
            attr_reader :id

            # If this variable corresponds to a Ruby variable of some kind, that variable's
            # identifier. This doesn't need to be an exact reference, since it's only used for
            # display.
            # @return [String, nil]
            attr_accessor :ruby_identifier

            # Create a new variable with a unique ID, optionally with a Ruby identifier.
            def initialize(ruby_identifier=nil)
                @@next_id ||= 1
                @id = @@next_id
                @@next_id += 1

                @ruby_identifier = ruby_identifier
            end

            def to_assembly
                "$#{id}" + (ruby_identifier ? "(#{ruby_identifier})" : "")
            end
        end

        # A block of sequential instructions, which can optionally introduce a new variable scope.
        class InstructionBlock
            # The instructions in the block.
            # @return [<Instruction>]
            attr_reader :instructions

            # The Ruby variables in the scope introduced at this block, or nil if this block doesn't
            # introduce a scope. All of these variables must have a `ruby_identifier` for 
            # resolution.
            # @return [<Variable>, nil]
            attr_reader :scope

            # The parameters of this block, if it is a method block or a function definition.
            # @return [<Variable>, nil]
            attr_reader :parameters

            # The instruction which this block belongs to.
            # @return [Instruction, nil]
            attr_reader :parent

            def initialize(instructions: nil, has_scope:, parameters: nil, parent:)
                @instructions = instructions || []
                @scope = has_scope ? [] : nil
                @parameters = parameters || []
                @parent = parent
            end

            # Returns the type of a variable at a particular instruction, either by reference or
            # index. If the type is not known, returns nil.
            # @param [Variable] var
            # @param [Instruction, Integer] ins
            # @return [Type, nil]
            def variable_type_at(var, ins, strictly_before: false)
                index = 
                    if ins.is_a?(Integer)
                        ins
                    else
                        instructions.index { |i| i.equal? ins } or raise 'invalid instruction ref'
                    end

                index -= 1 if strictly_before

                # Look for an instruction with a typechange for this variable
                until index < 0
                    # Is this a relevant typechange for this variable?
                    if instructions[index].result == var && !instructions[index].type_change.nil?
                        # We found a typechange! Return it
                        return instructions[index].type_change
                    end

                    # If the instruction is a conditional...
                    if instructions[index].is_a?(ConditionalInstruction)
                        # Find types for this variable in both branches, starting from the end
                        tbi = instructions[index].true_branch.instructions.last
                        fbi = instructions[index].false_branch.instructions.last

                        true_t = instructions[index].true_branch.variable_type_at(var, tbi)
                        false_t = instructions[index].false_branch.variable_type_at(var, fbi)

                        # The type is a union of both sides
                        return Houndstooth::Environment::UnionType.new([true_t, false_t]).simplify
                    end

                    # Move onto the previous instruction
                    index -= 1
                end
                
                # Check the parent if we have one
                parent&.block&.variable_type_at(var, parent, strictly_before: true)
            end

            # Identical to `variable_type_at`, but throws an exception on a missing type.
            def variable_type_at!(var, ins)
                variable_type_at(var, ins) or raise "assertion failed: missing type for #{var.to_assembly}"
            end

            # Gets the return type of this block - i.e. the type of its last variable assignment.
            # If the type is not known, returns nil.
            # @return [Type, nil]
            def return_type
                variable_type_at(instructions.last.result, instructions.last)
            end

            # Identical to `return_type`, but throws an exception on a missing type.
            def return_type!
                return_type or raise "assertion failed: missing return type"
            end
            
            # Returns the `Variable` instance by its Ruby identifier, for either a local variable
            # or a method block/definition parameter.
            # If the variable isn't present in this scope, it will look up scopes until it is found.
            # If `create` is set, the variable will be created in the closest scope if it doesn't
            # exist.
            # If the variable couldn't be found (and `create` is not set), throws an exception,
            # since this represents a mismatch in Ruby's state and our state.
            #
            # @param [String] name
            # @param [Boolean] create
            # @param [InstructionBlock, nil] highest_scope
            # @return [Variable]
            def resolve_local_variable(name, create:, highest_scope: nil)
                if !scope.nil?
                    highest_scope = self if highest_scope.nil? 

                    var = scope.find { |v| v.ruby_identifier == name }
                    return var if !var.nil?

                    var = parameters.find { |v| v.ruby_identifier == name }
                    return var if !var.nil?
                end

                if !parent.nil?
                    parent.block.resolve_local_variable(name, create: create, highest_scope: highest_scope)
                else
                    # Variable doesn't exist, create in highest scope
                    if create
                        new_var = Variable.new(name)
                        highest_scope.scope << new_var
                        new_var
                    else
                        raise "local variable #{name} doesn't exist in any block scope"
                    end
                end
            end

            def to_assembly
                ins = instructions.map { |ins| ins.to_assembly }.join("\n")

                if parameters.any?
                    "| #{parameters.map(&:to_assembly).join(", ")} |\n#{ins}"
                else
                    ins
                end
            end

            def walk(&blk)
                blk.(self)
                instructions.each do |instruction|
                    instruction.walk(&blk)
                end
            end
        end 

        # A minimal instruction in a sequence, translated from Ruby code.
        # @abstract
        class Instruction
            # The block which this instruction resides in.
            # @return [InstructionBlock]
            attr_accessor :block

            # The node which this instruction was derived from.
            # @return [SemanticNode]
            attr_accessor :node

            # The variable which the result of this instruction is assigned to.
            # @return [Variable]
            attr_accessor :result

            # If this instruction changes the type of the `result` variable, the new type.
            # To discover the type of a variable, you can traverse previous instructions and look
            # for the most recent type change (or, for things like conditional branches, combine
            # the type changes on the two conditional branches).
            # @return [Type, nil]
            attr_accessor :type_change
            
            def initialize(block:, node:, type_change: nil, generate_result: true)
                @block = block
                @node = node
                @result = generate_result ? Variable.new : nil
                @type_change = type_change
            end
            
            def to_assembly
                return "#{result.to_assembly}" \
                    + (self.type_change ? " -> #{self.type_change.rbs}" : "") \
                    + " = " \
                    # Print ????? if not overridden
                    + (self.class == Instruction ? "?????" : "")
            end

            def walk(&blk)
                blk.(self)
            end

            protected

            def assembly_indent(str)
                str.split("\n").map { |line| "  #{line}" }.join("\n")
            end
        end

        # An instruction which simply assigns the result variable to another (or the same) variable.
        # Unlike most instructions, this will not create a new implicit variable - this is used to
        # generate references to existing variables. For example:
        #
        #   x = 3
        #   puts x
        #
        # The `x` argument needs to generate an instruction, so generates the following:
        #
        #   $1(x) = 3
        #   $1(x) = existing $1(x)
        #   puts $1(x)
        #
        # The `result` and `variable` are different properties so that the `result` can be replaced
        # by future generations, for example:
        #
        #   x = 3
        #   y = x
        #
        # Would become:
        #
        #   $1(x) = 3
        #   $2(y) = existing $1(x)
        #   
        class AssignExistingInstruction < Instruction            
            def initialize(block:, node:, result:, variable:)
                super(block: block, node: node, generate_result: false)
                @result = result
                @variable = variable
            end

            # The variable to assign to the result.
            # @return [Variable]
            attr_accessor :variable

            def to_assembly
                "#{super}existing #{variable.to_assembly}"
            end
        end        

        # An instruction which assigns a literal value.
        class LiteralInstruction < Instruction
            # The constant value being assigned.
            # @return [Integer, Boolean, Float, String, Symbol, nil]
            attr_accessor :value
            
            def initialize(block:, node:, value:)
                super(block: block, node: node)
                @value = value
            end

            def to_assembly
                "#{super}literal #{value.inspect}"
            end
        end

        # An argument to a `SendInstruction`.
        # @abstract
        class Argument
            # The variable used for the argument's value.
            # @return [Variable]
            attr_accessor :variable

            def initialize(variable)
                @variable = variable
            end

            def to_assembly
                variable.to_assembly
            end
        end

        # A standard, singular, positional argument.
        class PositionalArgument < Argument; end

        # A singular keyword argument.
        class KeywordArgument < Argument
            # The keyword.
            # @return [String]
            attr_accessor :name

            def initialize(variable, name:)
                super(variable)
                @name = name.to_s
            end

            def to_assembly
                "#{name}: #{variable.to_assembly}"
            end
        end 

        # A method call on an object.
        class SendInstruction < Instruction
            # TODO: splats

            # The target of the method call.
            # @return [Variable]
            attr_accessor :target

            # The name of the method to call.
            # @return [Symbol]
            attr_accessor :method_name

            # The arguments to this call.
            # @return [<Argument>]
            attr_accessor :arguments

            # The block passed to this call.
            # @return [InstuctionBlock, nil]
            attr_accessor :method_block

            # If true, this isn't really a send, but instead a super call. The `target` and
            # `method_name` of this instance should be ignored.
            # It'll probably be possible to resolve this later, and make it a standard method call,
            # since we'll statically know the superclass.
            # @return [Boolean]
            attr_accessor :super_call

            def initialize(block:, node:, target:, method_name:, arguments: nil, method_block: nil, super_call: false)
                super(block: block, node: node)
                @target = target
                @method_name = method_name
                @arguments = arguments || []
                @method_block = method_block
                @super_call = super_call
            end

            def to_assembly
                args = arguments.map { |a| a.to_assembly }.join(", ")

                if super_call
                    "#{super}send_super #{args}"
                else
                    "#{super}send #{target.to_assembly} #{method_name} (#{args})"
                end + (method_block ? " block\n#{assembly_indent(method_block.to_assembly)}\nend" : '')
            end
        end

        # An instruction which assigns the value of `self`.
        class SelfInstruction < Instruction
            def to_assembly
                "#{super}self"
            end
        end

        # Convert something to a string for string or symbol interpolation.
        # This is not the same as just calling #to_s. When an object is interpolated, Ruby tries
        # calling #to_s first, and if it returns anything other than a string it uses a default
        # implementation.
        # See: https://stackoverflow.com/questions/25488902/what-happens-when-you-use-string-interpolation-in-ruby
        class ToStringInstruction < Instruction
            # The target to convert.
            # @return [Variable]
            attr_accessor :target

            def initialize(block:, node:, target:)
                super(block: block, node: node)
                @target = target
            end

            def to_assembly
                "#{super}to_string #{target.to_assembly}"
            end
        end

        # Execute one of two blocks for a final result, based on a condition.
        class ConditionalInstruction < Instruction
            # The condition to evaluate.
            # @return [Variable]
            attr_accessor :condition

            # The block to execute if true.
            # @return [InstructionBlock]
            attr_accessor :true_branch

            # The block to execute if false.
            # @return [InstructionBlock]
            attr_accessor :false_branch

            def initialize(block:, node:, condition:, true_branch:, false_branch:)
                super(block: block, node: node)
                @condition = condition
                @true_branch = true_branch
                @false_branch = false_branch
            end

            def to_assembly
                super +
                    "if #{condition.to_assembly}\n" \
                    "#{assembly_indent(true_branch.to_assembly)}\n" \
                    "else\n" \
                    "#{assembly_indent(false_branch.to_assembly)}\n" \
                    "end"
            end

            def walk(&blk)
                super
                true_branch.walk(&blk)
                false_branch.walk(&blk)
            end
        end

        # An access of the base constant value. For example, `::A` accesses `A` from the base.
        class ConstantBaseAccessInstruction < Instruction
            def to_assembly
                "#{super}constbase"
            end
        end

        # An access of a constant value, class, or module.
        class ConstantAccessInstruction < Instruction
            # A variable of the target from which to access this constant.
            # If `nil`, accesses from the current context.
            # @return [Variable, nil]
            attr_accessor :target

            # The name of the constant to access.
            # @return [Symbol]
            attr_accessor :name

            # Any type arguments passed alongside this constant access. When initially built, these
            # may be strings, as the instruction builder doesn't have access to the environment to
            # parse a type. They will be parsed and resolved to types later.
            # @return [<String, Type>]
            attr_accessor :type_arguments

            def initialize(block:, node:, name:, target:, type_arguments: nil)
                super(block: block, node: node)
                @name = name
                @target = target
                @type_arguments = type_arguments || []
            end

            def to_assembly
                "#{super}const #{target&.to_assembly || '(here)'} #{name}" \
                    + (type_arguments.any? ? " typeargs [#{
                        type_arguments.map { |t| t.is_a?(String) ? "<unparsed> #{t}" : t.rbs }.join(', ')
                    }]" : '')
            end
        end

        # A definition of a new class or module.
        class TypeDefinitionInstruction < Instruction
            # The name of the item being defined.
            # @return [Symbol]
            attr_accessor :name

            # The kind of definition: either :class or :module.
            # @return [Symbol]
            attr_accessor :kind

            # The constant on which the type is being defined.
            # If `nil`, defines on the current context.
            # @return [Variable, nil]
            attr_accessor :target

            # The superclass of this type, if it's a class.
            # @return [Variable, nil]
            attr_accessor :superclass

            # The block to execute to build the type definition.
            # @return [InstructionBlock]
            attr_accessor :body

            def initialize(block:, node:, name:, kind:, target:, superclass:, body:)
                super(block: block, node: node)
                @name = name
                @kind = kind
                @target = target
                @superclass = superclass
                @body = body
            end

            def to_assembly
                super +
                    "typedef #{kind} #{name} on #{target&.to_assembly || '(here)'}#{superclass ? " super #{superclass.to_assembly}" : ''}\n" \
                    "#{assembly_indent(body.to_assembly)}\n" \
                    "end"
            end

            def walk(&blk)
                super
                body.walk(&blk)
            end
        end

        # A definition of a new method.
        class MethodDefinitionInstruction < Instruction
            # The name of the item being defined.
            # @return [Symbol]
            attr_accessor :name

            # The target on which the method is being defined.
            # If `nil`, the method is defined on instances of `self`.
            # @return [Variable, nil]
            attr_accessor :target

            # The body of this method definition.
            # @return [InstructionBlock]
            attr_accessor :body

            def initialize(block:, node:, name:, target:, body:)
                super(block: block, node: node)
                @name = name
                @target = target
                @body = body
            end

            def to_assembly
                super +
                    "methoddef #{name} on #{target&.to_assembly || '(implicit)'}\n" \
                    "#{assembly_indent(body.to_assembly)}\n" \
                    "end"
            end

            def walk(&blk)
                super
                body.walk(&blk)
            end
        end
    end
end
