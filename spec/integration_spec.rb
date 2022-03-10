RSpec.describe 'integration tests' do
    def check_type_of(code, variable=nil, expect_success: true, &blk)
        $cli_options = {}

        # Prepare environment
        env = Houndstooth::Environment.new
        Houndstooth.process_file('stdlib.htt', File.read(File.join(__dir__, '..', 'types', 'stdlib.htt')), env)
        node = Houndstooth.process_file('test code', code, env)
        env.resolve_all_pending_types

        # Create instruction block
        block = Houndstooth::Instructions::InstructionBlock.new(has_scope: true, parent: nil)
        node.to_instructions(block)
        env.types["__HoundstoothMain"] = Houndstooth::Environment::DefinedType.new(path: "__HoundstoothMain")

        # Run the interpreter
        runtime = Houndstooth::Interpreter::Runtime.new(env: env)
        runtime.execute_from_top_level(block)
        
        # Skip type checking if any errors occured
        unless Houndstooth::Errors.errors.any?
            # Run type checker
            checker = Houndstooth::TypeChecker.new(env)
            checker.process_block(
                block,
                lexical_context: Houndstooth::Environment::BaseDefinedType.new,
                self_type: env.types["__HoundstoothMain"],
                const_context: false,
                type_parameters: [],
            )
        end

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

        # Blocks *could* execute, changing the type of a variable
        check_type_of('
            x = 3
            #!arg String
            ["x", "y", "z"].each do |y,|
                x = y
            end
        ', 'x') do |t|
            t.is_a?(E::UnionType) \
                && t.types.find { |t| t.type == resolve_type("Integer") } \
                && t.types.find { |t| t.type == resolve_type("String") }
        end

        # Blocks which don't affect the variable's type won't change it
        check_type_of('
            x = 3
            #!arg String
            ["x", "y", "z"].each do |y,|
                Kernel.puts y
            end
        ', 'x') { |t| t.type == resolve_type("Integer") }
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

    it 'allows usage of type parameters' do
        check_type_of('
            #!param T
            class X
                #: (T) -> T
                def identity(obj)
                    obj
                end
            end

            #!arg String
            x = X.new
            y = x.identity("Hello")
        ', 'y') { |t| t.type == resolve_type("String") }

        check_type_of('
            #!arg String
            x = Array.new
        ', 'x') do |t|
            t.type == resolve_type("Array") \
                && t.type_arguments.map(&:type) == [resolve_type("String")]
        end

        check_type_of('
            #!arg String
            x = Array.new
            y = (x << "foo")
        ', 'y') do |t|
            t.type == resolve_type("Array") \
                && t.type_arguments.map(&:type) == [resolve_type("String")]
        end

        check_type_of('
            #!arg String
            x = Array.new
            x << "foo"
            x << "bar"
            y = x[0]
        ', 'y') { |t| t.type == resolve_type("String") }

        check_type_of('
            #!arg String
            x = ["foo", "bar", "baz"]
        ', 'x') do |t|
            t.type == resolve_type("Array") \
                && t.type_arguments.map(&:type) == [resolve_type("String")]
        end

        check_type_of('
            #!arg String
            x = ["foo", 3, "baz"]
        ', expect_success: false)
    end

    it 'allows usage of instance variables' do
        check_type_of('
            #!var @name String
            class Person
                #: () -> String
                def name
                    @name
                end
            end

            x = Person.new.name
        ', 'x') { |t| t.type == resolve_type('String') }

        check_type_of('
            #!var @name String
            class Person
                #: (String) -> void
                def name=(n)
                    @name = n
                end

                #: () -> String
                def name
                    @name
                end
            end

            x = Person.new
            x.name = "Aaron"
            y = x.name
        ', 'y') { |t| t.type == resolve_type('String') }

        check_type_of('
            #!var @name String
            class Person
                #: () -> Integer
                def name
                    @name
                end
            end

            x = Person.new
            x.name = "Aaron"
            y = x.name
        ', expect_success: false)

        check_type_of('
            #!var @name String
            class Person
                #: (Object) -> void
                def name=(n)
                    @name = n
                end

                #: () -> String
                def name
                    @name
                end
            end

            x = Person.new
            x.name = "Aaron"
            y = x.name
        ', expect_success: false)
    end

    it 'recognises is_a? to refine types back' do
        check_type_of('
            if Kernel.rand > 0.5
                x = 3
            else
                x = "hello"
            end
            
            if x.is_a?(Integer)
                y = x.abs
            end
        ', 'y') do |t|
            t.is_a?(E::UnionType) \
                && t.types.find { |t| t.type == resolve_type("Integer") } \
                && t.types.find { |t| t.type == resolve_type("NilClass") }
        end
    end

    it 'checks that const-required calls are used in const contexts' do
        # Call to const-required-internal from type definition body
        check_type_of('
            class X
                #: () -> String
                def foo
                    "foo"
                end

                private :foo
            end
        ')

        # Call from non-const context
        check_type_of('
            class X
                #: () -> String
                def foo
                    "foo"
                end

                if Kernel.rand > 0.5
                    private :foo
                end
            end
        ', expect_success: false)

        # Call to const-required-internal from const-required, and then call to that const-required
        # from type definition body
        check_type_of('
            class X
                #: (Symbol, Symbol) -> void
                #!const required
                def self.private_two(x, y)
                    private x
                    private y
                end

                #: () -> void
                def foo; end

                #: () -> void
                def bar; end

                private_two :foo, :bar
            end
        ')
    end

    it 'checks that const methods call other only other const methods' do        
        # Valid - calls only const-internal methods
        check_type_of('
            class X
                #: (Integer, Integer) -> Integer
                #!const
                def add_two(x, y)
                    x + y
                end
            end

            x = X.new.add_two(1, 2)
        ', 'x') { |t| t.type == resolve_type('::Integer') }

        # Valid - calls another const method
        check_type_of('
            class X
                #: (Integer, Integer, Integer) -> Integer
                #!const
                def add_three(x, y, z)
                    add_two(add_two(x, y), z)
                end

                #: (Integer, Integer) -> Integer
                #!const
                def add_two(x, y)
                    x + y
                end
            end

            x = X.new.add_three(1, 2, 3)
        ', 'x') { |t| t.type == resolve_type('::Integer') }

        # Invalid - calls non-const from const
        check_type_of('
            class X
                #: () -> Float
                #!const
                def fake_const_float
                    Kernel.rand
                end
            end
        ', expect_success: false)
    end

    it 'allows type parameters on methods' do
        # Normal call
        check_type_of('
            module X
                #: [A] (A) -> A
                def self.identity(x)
                    x
                end
            end

            x = X
                #!arg Integer
                .identity(3)
        ', 'x') { |t| t.type == resolve_type('Integer') }

        # Insufficient type arguments
        check_type_of('
            module X
                #: [A] (A) -> A
                def self.identity(x)
                    x
                end
            end

            x = X.identity(3)
        ', expect_success: false)

        # Unexpected type arguments
        check_type_of('
            Kernel.
                #!arg String
                puts "hello"
        ', expect_success: false)

        # Passing type arguments through calls
        check_type_of('
            module X
                #: [T] (T) -> T
                def self.identity(x)
                    x
                end
                
                #: [T] (T) -> T
                def self.indirect_identity(x)
                    #!arg T
                    identity(x)
                end
            end
            
            x = X
                #!arg Integer
                .indirect_identity(3)
        ', 'x') { |t| t.type == resolve_type('Integer') }
    end
end
