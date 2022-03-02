module Houndstooth::Interpreter
    # Provides definitions for `#!const internal` methods in the standard library.
    class ConstInternal
        def initialize(env:)
            @method_definitions = {}

            # Initialize adding methods
            add = ->(this, other) do
                InterpreterObject.from_value(
                    value: this.unwrap_primitive_value + other.unwrap_primitive_value,
                    env: env,
                )
            end
            ['::Numeric', '::Integer', '::Float'].each do |t|
                @method_definitions[env.resolve_type(t).resolve_instance_method(:+, env)] = add     
            end

            # puts and print
            puts_print = ->(*_) { InterpreterObject.from_value(value: nil, env: env) }
            kernel = env.resolve_type('::Kernel').eigen
            [:puts, :print].each do |m|
                @method_definitions[kernel.resolve_instance_method(m, env)] = puts_print
            end
        end

        # @return [Environment]
        attr_accessor :env

        # A hash of the method definitions. Access with the environment's method reference, call the
        # given proc with the self value and argument values, and it will return a new object as the
        # result.
        # @return [{Method => Proc}]
        attr_accessor :method_definitions
    end
end
