RSpec.describe TypeChecker::Environment do
    E = TypeChecker::Environment

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

    it 'can resolve types' do
        subject.add_type E::DefinedType.new(path: 'A')
        subject.add_type E::DefinedType.new(path: 'A::B')
        subject.add_type E::DefinedType.new(path: 'A::B::A')
        subject.add_type E::DefinedType.new(path: 'A::C')
        subject.add_type E::DefinedType.new(path: 'A::D')
        subject.add_type E::DefinedType.new(path: 'B')
        subject.add_type E::DefinedType.new(path: 'B::A')
        subject.add_type E::DefinedType.new(path: 'E')

        t = subject.types

        expect(subject.resolve_type('A')).to eq t['A']
        expect(subject.resolve_type('A::B')).to eq t['A::B']
        expect(subject.resolve_type('B::A')).to eq t['B::A']

        expect(subject.resolve_type('A', type_context: t['A'])).to eq t['A']
        expect(subject.resolve_type('E', type_context: t['A'])).to eq t['E']
        expect(subject.resolve_type('B', type_context: t['A'])).to eq t['A::B']
        expect(subject.resolve_type('B', type_context: t['A::B'])).to eq t['A::B']
        expect(subject.resolve_type('A', type_context: t['A::B::A'])).to eq t['A::B::A']
        expect(subject.resolve_type('::A', type_context: t['A::B::A'])).to eq t['A']
        expect(subject.resolve_type('A', type_context: t['B'])).to eq t['B::A']
    end

    it 'can parse RBS signatures into our type model' do
        expect(E::TypeParser.parse_method_type '(String, Object) -> Integer').to m(
            E::MethodType,
            positional_parameters: [
                m(E::PositionalParameter, name: nil, type: m(E::PendingDefinedType, path: "String")),
                m(E::PositionalParameter, name: nil, type: m(E::PendingDefinedType, path: "Object")),
            ],
            return_type: m(E::PendingDefinedType, path: "Integer"),
        )

        expect(E::TypeParser.parse_method_type '(A a, ?B b, *E e, c: C, ?d: D, **F f) -> R').to m(
            E::MethodType,
            positional_parameters: [
                m(E::PositionalParameter, name: :a, type: m(E::PendingDefinedType, path: "A")),
                m(E::PositionalParameter, name: :b, type: m(E::PendingDefinedType, path: "B"), optional: true),
            ],
            keyword_parameters: [
                m(E::KeywordParameter, name: :c, type: m(E::PendingDefinedType, path: "C")),
                m(E::KeywordParameter, name: :d, type: m(E::PendingDefinedType, path: "D"), optional: true),
            ],
            rest_positional_parameter: m(E::PositionalParameter, name: :e, type: m(E::PendingDefinedType, path: "E")),
            rest_keyword_parameter: m(E::KeywordParameter, name: :f, type: m(E::PendingDefinedType, path: "F")),
            return_type: m(E::PendingDefinedType, path: "R"),
        )

        expect(E::TypeParser.parse_method_type '() { (Integer) -> Integer } -> void').to m(
            E::MethodType,
            block_parameter: m(
                E::BlockParameter,
                optional: false,
                type: m(
                    E::MethodType,
                    positional_parameters: [
                        m(E::PositionalParameter, name: nil, type: m(E::PendingDefinedType, path: "Integer")),
                    ],
                    return_type: m(E::PendingDefinedType, path: "Integer"),
                ),
            ),
            return_type: m(E::VoidType),
        )
    end
end
