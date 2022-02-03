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

            # The type of this variable. This will start as `nil` before resolution, and then be
            # resolved later.
            # @return [Type, nil]
            attr_accessor :type

            # Create a new variable with a unique ID, optionally with a Ruby identifier.
            def initialize(ruby_identifier=nil)
                @@next_id ||= 1
                @id = @@next_id
                @@next_id += 1

                @ruby_identifier = ruby_identifier
            end

            def to_assembly
                "$#{id}" +
                    (ruby_identifier ? "(#{ruby_identifier})" : "") +
                    (type ? "<#{type.rbs}>" : "")
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

            # The parent of this block.
            # @return [InstructionBlock, nil]
            attr_reader :parent

            def initialize(instructions: nil, has_scope:, parent:)
                @instructions = instructions || []
                @scope = has_scope ? [] : nil
                @parent = parent
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
            # The node which this instruction was derived from.
            # @return [SemanticNode]
            attr_accessor :node

            # The variable which the result of this instruction is assigned to.
            # @return [Variable]
            attr_accessor :result

            def initialize(node:)
                @node = node
                @result = Variable.new
            end
            
            def to_assembly
                "#{result.to_assembly} = ?????"
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
            
            def initialize(node:, value:)
                super(node: node)
                @value = value
            end

            def to_assembly
                "#{result.to_assembly} = #{value.inspect}"
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

            def initialize(node:, target:, method_name:, positional_arguments: nil, keyword_arguments: nil, super_call: false)
                super(node: node)
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
                    "#{result.to_assembly} = send_super "
                else
                    "#{result.to_assembly} = send #{target.to_assembly} #{method_name} "
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
                "#{result.to_assembly} = self"
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

            def initialize(node:, target:)
                super(node: node)
                @target = target
            end

            def to_assembly
                "#{result.to_assembly} = to_string #{target.to_assembly}"
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

            def initialize(node:, condition:, true_branch:, false_branch:)
                super(node: node)
                @condition = condition
                @true_branch = true_branch
                @false_branch = false_branch
            end

            def to_assembly
                "#{result.to_assembly} = if #{condition.to_assembly}\n" \
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
