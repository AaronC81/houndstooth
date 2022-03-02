RSpec.describe Houndstooth::Interpreter do
    Iptr = Houndstooth::Interpreter

    def interpret(code, local=nil)
        env = Houndstooth::Environment.new
        Houndstooth::Stdlib.add_types(env)

        Houndstooth.process_file('(test)', code, env)

        block = code_to_block(code)
        runtime = Iptr::Runtime.new(env: env)
        runtime.execute_block(
            block,
            self_type: nil,
            self_object: nil,
            lexical_context: Houndstooth::Environment::BaseDefinedType.new,
        )

        if local
            [env, runtime.variables.find { |var, t| var.ruby_identifier == local }[1]]
        else
            [env, runtime]
        end
    end

    it 'can unwrap primitive values' do
        env = Houndstooth::Environment.new
        Houndstooth::Stdlib.add_types(env)

        # Unwrap where value given
        known_int = Iptr::InterpreterObject.new(
            type: env.resolve_type('Integer'),
            env: env,
            primitive_value: [true, 3],
        )
        expect(known_int.unwrap_primitive_value).to eq 3

        # Unwrap where value not given (e.g. created with .new)
        default_int = Iptr::InterpreterObject.new(
            type: env.resolve_type('Integer'),
            env: env,
        )
        expect(default_int.unwrap_primitive_value).to eq 0

        # Can't unwrap non-primitive
        expect do
            Iptr::InterpreterObject.new(
                type: env.resolve_type('Object'),
                env: env,
            ).unwrap_primitive_value
        end.to raise_error(RuntimeError)
    end

    it 'assigns objects truthiness' do
        env = Houndstooth::Environment.new
        Houndstooth::Stdlib.add_types(env)

        fals = Iptr::InterpreterObject.new(
            type: env.resolve_type('FalseClass'),
            env: env,
        )
        expect(fals.truthy?).to eq false

        nl = Iptr::InterpreterObject.new(
            type: env.resolve_type('NilClass'),
            env: env,
        )
        expect(nl.truthy?).to eq false

        tru = Iptr::InterpreterObject.new(
            type: env.resolve_type('TrueClass'),
            env: env,
        )
        expect(tru.truthy?).to eq true

        int = Iptr::InterpreterObject.new(
            type: env.resolve_type('Integer'),
            env: env,
        )
        expect(int.truthy?).to eq true
    end

    it 'can execute basic literal evaluations' do
        env, x = interpret('x = 3', 'x')
        expect(x).to m(Iptr::InterpreterObject,
            type: env.resolve_type('Integer'),
            primitive_value: [true, 3]
        )
    end

    it 'can send to const internal methods' do
        env, x = interpret('x = 2 + 3', 'x')
        expect(x).to m(Iptr::InterpreterObject,
            type: env.resolve_type('Integer'),
            primitive_value: [true, 5]
        )
    end
    
    it 'recurses into definitions' do
        env, x = interpret('class X; class Y; x = 3; end; end', 'x')
        expect(x).to m(Iptr::InterpreterObject,
            type: env.resolve_type('Integer'),
            primitive_value: [true, 3]
        )
    end
end
