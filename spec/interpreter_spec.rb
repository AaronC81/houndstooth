RSpec.describe Houndstooth::Interpreter do
    Iptr = Houndstooth::Interpreter

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
end
