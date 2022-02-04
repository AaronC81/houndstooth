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

            # The instruction which this block belongs to.
            # @return [Instruction, nil]
            attr_reader :parent

            def initialize(instructions: nil, has_scope:, parent:)
                @instructions = instructions || []
                @scope = has_scope ? [] : nil
                @parent = parent
            end

            # Returns the type of a variable at a particular instruction, either by reference or
            # index. If the type is not known, returns nil.
            # @param [Variable] var
            # @param [Instruction, Integer] ins
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
            end

            def to_assembly
                instructions.map { |ins| ins.to_assembly }.join("\n")
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
            
            def initialize(block:, node:, type_change: nil)
                @block = block
                @node = node
                @result = Variable.new
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
                "#{super}#{value.inspect}"
            end
        end

        # A method call on an object.
        class SendInstruction < Instruction
            # TODO: blocks
            # TODO: splats

            # The target of the method call.
            # @return [Variable]
            attr_accessor :target

            # The name of the method to call.
            # @return [Symbol]
            attr_accessor :method_name

            # The positional arguments to pass with the call.
            # @return [<Variable>]
            attr_accessor :positional_arguments

            # The keyword arguments to pass with the call.
            # @return [{String => Variable}]
            attr_accessor :keyword_arguments

            # If true, this isn't really a send, but instead a super call. The `target` and
            # `method_name` of this instance should be ignored.
            # It'll probably be possible to resolve this later, and make it a standard method call,
            # since we'll statically know the superclass.
            # @return [Boolean]
            attr_accessor :super_call

            def initialize(block:, node:, target:, method_name:, positional_arguments: nil, keyword_arguments: nil, super_call: false)
                super(block: block, node: node)
                @target = target
                @method_name = method_name
                @positional_arguments = positional_arguments || []
                @keyword_arguments = keyword_arguments || {}
                @super_call = super_call
            end

            def to_assembly
                pa = positional_arguments.map { |a| a.to_assembly }.join(", ")
                ka = keyword_arguments.map { |n, a| "#{n}: #{a.to_assembly}" }.join(", ")

                if super_call
                    "#{super}send_super "
                else
                    "#{super}send #{target.to_assembly} #{method_name} "
                end +
                    (ka != "" ? "(#{pa} | #{ka})" : "(#{pa})")
            end
        end

        # An instruction which assigns the value of `self`.
        # TODO: How do we know what this is?
        # Maybe encode the type of `self` in `InstructionBlock` if it introduces a new one (like how
        # scopes work)
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
    end
end
