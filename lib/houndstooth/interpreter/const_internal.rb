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
            ['::Numeric', '::Integer', '::Float', '::String'].each do |t|
                @method_definitions[env.resolve_type(t).resolve_instance_method(:+, env)] = add     
            end

            # to_sym
            @method_definitions[env.resolve_type('::String').resolve_instance_method(:to_sym, env)] =
                ->(this, **_) do
                    InterpreterObject.from_value(value: this.unwrap_primitive_value.to_sym, env: env)
                end

            # times
            @method_definitions[env.resolve_type('::Integer').resolve_instance_method(:times, env)] =
                ->(this, call_block:, **_) do
                    this.unwrap_primitive_value.times do |i|
                        call_block.([InterpreterObject.from_value(value: i, env: env)])
                    end

                    this
                end

            # Array.new
            @method_definitions[env.resolve_type('::Array').eigen.resolve_instance_method(:new, env)] =
                ->(this, **_) do
                    InterpreterObject.from_value(value: [], env: env)
                end

            # Array#<<
            @method_definitions[env.resolve_type('::Array').resolve_instance_method(:<<, env)] =
                ->(this, item, **_) do
                    this.unwrap_primitive_value << item
                    this
                end
                
            # Array#each
            @method_definitions[env.resolve_type('::Array').resolve_instance_method(:each, env)] =
                ->(this, call_block:, **_) do
                    items = this.unwrap_primitive_value
                    items.each do |item|
                        call_block.([item])
                    end

                    this
                end

            # puts and print
            kernel = env.resolve_type('::Kernel').eigen
            @method_definitions[kernel.resolve_instance_method(:puts, env)] = ->(_, obj, **_) do
                $const_printed = true
                if obj.primitive_value.first
                    puts obj.unwrap_primitive_value
                else
                    puts obj.inspect
                end
            end
            @method_definitions[kernel.resolve_instance_method(:print, env)] = ->(_, obj, **_) do
                $const_printed = true
                if obj.primitive_value.first
                    print obj.unwrap_primitive_value
                else
                    print obj.inspect
                end
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

            # define_method
            @method_definitions[env.resolve_type('::Class').eigen.resolve_instance_method(:define_method, env)] =
                ->(this, name, type_arguments:, **_) do
                    # Get all argument types and return type
                    arg_types = (type_arguments.length - 1).times.map do |i|
                        type_arguments["A#{i + 1}"].substitute_type_parameters(nil, type_arguments)
                    end
                    return_type = type_arguments['R'].substitute_type_parameters(nil, type_arguments)

                    # Create method
                    env.resolve_type(this.type.uneigen).instance_methods << Houndstooth::Environment::Method.new(
                        name.unwrap_primitive_value,
                        [
                            Houndstooth::Environment::MethodType.new(
                                positional: arg_types.map.with_index do |t, i|
                                    Houndstooth::Environment::PositionalParameter.new(
                                        "__anon_param_#{i}",
                                        t,
                                    )
                                end,
                                return_type: return_type,
                            )
                        ]
                    )
                    InterpreterObject.from_value(value: nil, env: env)
                end

            # Various env-changing methods are a no-op for now
            nil_method = ->(*_, **_) { InterpreterObject.from_value(value: nil, env: env) }
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
