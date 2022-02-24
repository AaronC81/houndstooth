module Houndstooth::Interpreter
    # An instance of a defined type.
    class InterpreterObject
        def initialize(type:, env:, primitive_value: nil)
            @type = type
            @env = env
            @instance_variables = {}
            @primitive_value = primitive_value || [false, nil]
        end

        # The type which this is an instance of.
        # @return [DefinedType]
        attr_accessor :type

        # The type environment in which this object exists.
        # @return [Environment]
        attr_accessor :env
        
        # The instance variables on this instance.
        # @return [{String => InterpreterObject}]
        attr_accessor :instance_variables

        # The primitive value on this instance, if it has one.
        # A tuple of the form [present, value].
        # @return [(Boolean, Object)]
        attr_accessor :primitive_value

        def unwrap_primitive_value
            present, value = primitive_value

            default = 
                case type
                when env.resolve_type('::Integer')
                    0
                when env.resolve_type('::String')
                    ''
                when env.resolve_type('::Boolean')
                    false
                when env.resolve_type('::Float')
                    0.0
                
                # These always have particular values, so just return immediately and ignore
                # whatever the value might be set to
                when env.resolve_type('::NilClass')
                    return nil
                when env.resolve_type('::FalseClass')
                    return false
                when env.resolve_type('::TrueClass')
                    return false
                
                else
                    raise 'internal error: tried to unwrapp primitive where type isn\'t primitive'
                end

            if present
                value
            else
                default
            end
        end

        def falsey?
            type == env.resolve_type('NilClass') || type == env.resolve_type('FalseClass')
        end

        def truthy?
            !falsey?
        end
    end
end
