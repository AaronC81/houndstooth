module Houndstooth::Interpreter
    # Provides definitions for `#!const internal` methods in the standard library.
    class ConstInternal
        def initialize(env:)
            @method_definitions = {}

            # Initialize adding methods
            add = ->(this, other, **_) do
                InterpreterObject.from_value(
                    value: this.unwrap_primitive_value + other.unwrap_primitive_value,
                    env: env,
                )
            end
            ['::Numeric', '::Integer', '::Float'].each do |t|
                @method_definitions[env.resolve_type(t).resolve_instance_method(:+, env)] = add     
            end

            # puts and print
            nil_method = ->(*_, **_) { InterpreterObject.from_value(value: nil, env: env) }
            kernel = env.resolve_type('::Kernel').eigen
            [:puts, :print].each do |m|
                @method_definitions[kernel.resolve_instance_method(m, env)] = nil_method
            end

            # attr_reader
            @method_definitions[env.resolve_type('::Class').eigen.resolve_instance_method(:attr_reader, env)] =
                ->(this, name, type_arguments:, **_) do
                    t = type_arguments['T']
                    t = t.substitute_type_parameters(nil, type_arguments)

                    env.resolve_type(this.type.uneigen).instance_methods << Houndstooth::Environment::Method.new(
                        name.unwrap_primitive_value,
                        [
                            Houndstooth::Environment::MethodType.new(
                                return_type: t,
                            )
                        ]
                    )
                    InterpreterObject.from_value(value: nil, env: env)
                end

            # Various env-changing methods are a no-op for now
            [:private, :protected].each do |m|
                @method_definitions[env.resolve_type('::Class').eigen.resolve_instance_method(m, env)] = nil_method
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
