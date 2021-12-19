RSpec.describe TypeChecker::Environment do
    before :each do
        TypeChecker::Stdlib.types.each do |type|
            subject.add_type(type)
        end
    end

    it 'can resolve methods' do
        cases = [
            # Target type      Method       Valid?
            ['<Eigen:Object>', :new,        true ], # Object.new - defined here
            ['Object',         :new,        false], # Object.new.new - not OK

            ['<Eigen:Class>',  :new,        true ], # Class.new - inherited from <Eigen:Object>
            ['Class',          :new,        true ], # Class.new.new - defined here

            ['<Eigen:Class>',  :superclass, true ], # Class.superclass - defined here
            ['Class',          :superclass, true ], # Class.new.superclass - defined here

            ['<Eigen:String>', :new,        true ], # String.new - inherited from <Eigen:Object>
            ['<Eigen:String>', :superclass, true ], # String.superclass - inherited from <Eigen:Class>
            ['String',         :superclass, false], # "foo".superclass - not OK

            ['String',         :inspect,    true ], # "foo".inspect - inherited from Object
            ['String',         :length,     true ], # "foo".length - defined here

            ['<Eigen:String>', :nesting,    true ], # String.nesting - inherited from Module
            ['String',         :nesting,    false], # "foo" - not OK
        ]

        cases.each do |type, method, valid|
            expect(subject.types[type].resolve_instance_method(method)).send(valid ? :not_to : :to, be_nil)
        end
    end
end
