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
                # Clear errors so test does not fail later
                Houndstooth::Errors.reset
                return
            else
                raise 'no error occurred but expected one'
            end
        end

        if variable
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
    end

    it 'assigns types literals' do
        check_type_of('x = 3', 'x') { |t| t.type == resolve_type('Integer') }
        check_type_of('x = "hello"', 'x') { |t| t.type == resolve_type('String') }
        check_type_of('x = 3.2', 'x') { |t| t.type == resolve_type('Float') }
        check_type_of('x = true', 'x') { |t| t.type == resolve_type('TrueClass') }
        check_type_of('x = nil', 'x') { |t| t.type == resolve_type('NilClass') }
    end

    it 'resolves methods and selects appropriate overloads' do
        # Basic resolution
        check_type_of('x = (-3).abs', 'x') { |t| t.type == resolve_type('Integer') }

        # Overload selection
        check_type_of('x = 3 + 3', 'x') { |t| t.type == resolve_type('Integer') }
        check_type_of('x = 3 + 3.2', 'x') { |t| t.type == resolve_type('Float') }
        check_type_of('x = 3.2 + 3', 'x') { |t| t.type == resolve_type('Float') }

        # Errors
        check_type_of('x = 3.non_existent_method', expect_success: false) # Method doesn't exist
        check_type_of('x = 3.+()', expect_success: false) # Too few arguments
        check_type_of('x = 3.+(1, 2, 3)', expect_success: false) # Too many arguments
    end

    it 'checks blocks passed to methods' do
        # Correct usage
        # (procarg not supported yet, hence |x,|)
        check_type_of('3.times { |x,| Kernel.puts 1 + x }')

        # Incorrect usages
        check_type_of('3.times { || Kernel.puts x }', expect_success: false) # Too few params
        check_type_of('3.times { |x, y| Kernel.puts x }', expect_success: false) # Too many params
        check_type_of('3.times { |x| Kernel.puts x }', expect_success: false) # Unsupported param
        check_type_of('3.times', expect_success: false) # Missing block
        check_type_of('1.+(1) { |x| "what" }', expect_success: false) # Block where not taken
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
                && t.types.find { |t| t.type == resolve_type("Integer") } \
                && t.types.find { |t| t.type == resolve_type("String") }
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
                && t.types.find { |t| t.type == resolve_type("Float") } \
                && t.types.find { |t| t.type == resolve_type("String") }
        end

        # Both branches assign to the same type
        check_type_of('
            x = 3
            if Kernel.rand
                x = "hello"
            else
                x = "goodbye"
            end
        ', 'x') { |t| t.type == resolve_type("String") }
    end

    it 'checks module definitions' do
        # Module definition
        check_type_of('
            module A
                #: () -> String
                def self.foo
                    "Hello"
                end

                #: () -> String
                def self.bar
                    "there"
                end
            end

            x = A.foo + " " + A.bar
        ', 'x') { |t| t.type == resolve_type("String") }

        # Module methods are available on defined modules
        check_type_of('
            module A
                #: () -> String
                def self.foo
                    "Hello"
                end

                #: () -> String
                def self.bar
                    "there"
                end
            end

            x = A.nesting
        ') # TODO: make more precise once arrays exist

        # Methods defined on one module don't exist on another
        # (i.e. eigens are probably isolated)
        check_type_of('
            module A
                #: () -> String
                def self.foo
                    "Hello"
                end
            end

            module B
                #: () -> String
                def self.bar
                    "there"
                end
            end

            x = B.foo
        ', expect_success: false)

        # Non-self methods can't be called on modules directly
        check_type_of('
            module A
                #: () -> String
                def foo
                    "hello"
                end
            end

            A.foo
        ', expect_success: false)
    end

    it 'checks class definitions' do
        # Class definition, with both instance and static methods
        check_type_of('
            class A
                #: () -> String
                def foo
                    "Hello"
                end

                #: () -> String
                def self.bar
                    "there"
                end
            end

            x = A.new.foo + " " + A.bar
        ', 'x') { |t| t.type == resolve_type("String") }

        # Subclassing
        check_type_of('
            class A
                #: () -> String
                def foo
                    "Hello"
                end
            end

            class B < A
                #: () -> String
                def bar
                    "there"
                end
            end

            b = B.new
            x = b.foo + " " + b.bar
        ', 'x') { |t| t.type == resolve_type("String") }

        # Pulls constructor parameters into `new`
        check_type_of('
            class Person
                #: (String, Integer) -> void
                def initialize(name, age)
                    Kernel.puts "Created #{name}, who is #{age}"
                end
            end

            x = Person.new("Aaron", 21)
        ', 'x') { |t| t.type == resolve_type("Person") }
    end

    it 'checks method definitions' do
        # Basic checking
        check_type_of('
            class A
                #: (Integer, Integer) -> Integer
                def add(a, b)
                    a + b
                end
            end
        ')
        check_type_of('
            class A
                #: (String) -> Integer
                def foo(x)
                    foo.abs
                end
            end
        ', expect_success: false)

        # Parameter count mismatch
        check_type_of('
            class A
                #: (Integer) -> Integer
                def add(a, b)
                    a + b
                end
            end
        ', expect_success: false)
        check_type_of('
            class A
                #: (Integer, Integer) -> Integer
                def foo(a)
                    a
                end
            end
        ', expect_success: false)

        # Must have a signature
        check_type_of('
            class A
                def foo(a)
                    a
                end
            end
        ', expect_success: false)

        # If the definition has multiple signatures, they're all checked
        check_type_of('
            class A
                #: (Float, Float) -> Float
                #: (Integer, Integer) -> Integer
                #: (String, String) -> String
                def add(a, b)
                    a + b
                end
            end
        ')
        check_type_of('
            class A
                #: (Float, Float) -> Float
                #: (Integer, Integer) -> Integer
                #: (String, String) -> String
                #: (Object, Object) -> Object
                def add(a, b)
                    a + b
                end
            end
        ', expect_success: false)
    end

    it 'checks plain code inside type definitions' do
        # Checks actual snippets of code in definitions
        check_type_of('
            class X
                Kernel.puts 2 + 2
            end
        ')
        check_type_of('
            class X
                Kernel.puts 2 + "hello"
            end
        ', expect_success: false)
    end
end
