RSpec.describe 'integration tests' do
    def check_type_of(code, variable=nil, expect_success: true, &blk)
        # Prepare environment
        env = Houndstooth::Environment.new
        Houndstooth.process_file('stdlib.htt', File.read(File.join(__dir__, '..', 'types', 'stdlib.htt')), env)
        node = Houndstooth.process_file('test code', code, env)
        env.resolve_all_pending_types

        # Create instruction block
        block = Houndstooth::Instructions::InstructionBlock.new(has_scope: true, parent: nil)
        node.to_instructions(block)
        env.types["__HoundstoothMain"] = Houndstooth::Environment::DefinedType.new(path: "__HoundstoothMain")

        # Run type checker
        checker = Houndstooth::TypeChecker.new(env)
        checker.process_block(
            block,
            lexical_context: Houndstooth::Environment::BaseDefinedType.new,
            self_type: env.types["__HoundstoothMain"]
        )

        # If we're expecting success, throw exception if there was an error
        raise 'unexpected type errors' if expect_success && Houndstooth::Errors.errors.any?

        # If we're not expecting success, check an error occured
        if !expect_success
            if Houndstooth::Errors.errors.any?
                return
            else
                raise 'no error occurred but expected one'
            end
        end

        # Very aggressively look for the variable and grab its type
        # (It might only exist in an inner scope)
        var = nil
        block.walk do |n|
            if n.is_a?(Houndstooth::Instructions::InstructionBlock)
                var = n.resolve_local_variable(variable, create: false) rescue nil
                break unless var.nil?
            end
        end

        raise "couldn't find variable #{variable}" if var.nil?
        type = block.variable_type_at!(var, block.instructions.last)

        raise "type check for #{code} failed" if !env.instance_exec(type, &blk)
    end

    it 'assigns types literals' do
        check_type_of('x = 3', 'x') { |t| t == resolve_type('Integer') }
        check_type_of('x = "hello"', 'x') { |t| t == resolve_type('String') }
        check_type_of('x = 3.2', 'x') { |t| t == resolve_type('Float') }
        check_type_of('x = true', 'x') { |t| t == resolve_type('TrueClass') }
        check_type_of('x = nil', 'x') { |t| t == resolve_type('NilClass') }
    end

    it 'creates unions from flow-sensitivity' do
        # True branch assigns
        check_type_of('
            x = 3
            if Kernel.rand
                x = "hello"
            else
                y = 2
            end
        ', 'x') do |t|
            t.is_a?(E::UnionType) \
                && t.types.include?(resolve_type("Integer")) \
                && t.types.include?(resolve_type("String"))
        end

        # Both branches assign to different types
        check_type_of('
            x = 3
            if Kernel.rand
                x = "hello"
            else
                x = 3.2
            end
        ', 'x') do |t|
            t.is_a?(E::UnionType) \
                && t.types.include?(resolve_type("Float")) \
                && t.types.include?(resolve_type("String"))
        end

        # Both branches assign to the same type
        check_type_of('
            x = 3
            if Kernel.rand
                x = "hello"
            else
                x = "goodbye"
            end
        ', 'x') { |t| t == resolve_type("String") }
    end
end
