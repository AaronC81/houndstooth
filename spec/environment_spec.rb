RSpec.describe Houndstooth::Environment do
    E = Houndstooth::Environment

    def resolve(t)
        t.resolve_all_pending_types(subject, context: nil)
        t
    end

    before :each do
        Houndstooth::Stdlib.add_types(subject)
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
            expect(subject.types[type].resolve_instance_method(method, subject)).send(valid ? :not_to : :to, be_nil)
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
        expect(resolve(E::TypeParser.parse_method_type('(String, Object) -> Integer'))).to m(
            E::MethodType,
            positional_parameters: [
                m(E::PositionalParameter, name: nil, type: m(E::TypeInstance, type: m(E::DefinedType, path: "String"))),
                m(E::PositionalParameter, name: nil, type: m(E::TypeInstance, type: m(E::DefinedType, path: "Object"))),
            ],
            return_type: m(E::TypeInstance, type: m(E::DefinedType, path: "Integer")),
        )

        expect(E::TypeParser.parse_method_type '(A a, ?B b, *E e, c: C, ?d: D, **F f) -> R').to m(
            E::MethodType,
            positional_parameters: [
                m(E::PositionalParameter, name: :a, type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "A"))),
                m(E::PositionalParameter, name: :b, type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "B")), optional: true),
            ],
            keyword_parameters: [
                m(E::KeywordParameter, name: :c, type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "C"))),
                m(E::KeywordParameter, name: :d, type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "D")), optional: true),
            ],
            rest_positional_parameter: m(E::PositionalParameter, name: :e, type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "E"))),
            rest_keyword_parameter: m(E::KeywordParameter, name: :f, type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "F"))),
            return_type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "R")),
        )

        expect(resolve(E::TypeParser.parse_method_type('() { (Integer) -> Integer } -> void'))).to m(
            E::MethodType,
            block_parameter: m(
                E::BlockParameter,
                optional: false,
                type: m(
                    E::MethodType,
                    positional_parameters: [
                        m(E::PositionalParameter, name: nil, type: m(E::TypeInstance, type: m(E::DefinedType, path: "Integer"))),
                    ],
                    return_type: m(E::TypeInstance, type: m(E::DefinedType, path: "Integer")),
                ),
            ),
            return_type: m(E::VoidType),
        )
    end
    
    it 'can be built using the builder' do
        include Houndstooth::SemanticNode
        node = code_to_semantic_node("
            module A
                class B
                    class C
                        def c1
                        end

                        #: () -> String
                        def c2
                            'c2'
                        end
                    end
                end

                module D
                    class ::E
                        #: (Object) -> Object
                        #: (String) -> String
                        def e
                            magic!
                        end
                    end
                end

                class F
                    module G
                    end
                end
            end
        ")
        E::Builder.new(node, subject).analyze

        expect(subject.types.keys).to include(
            "A",
            "A::B",
            "A::B::C",
            "A::D",
            "A::F",
            "A::F::G",
            "E",
        )

        expect(subject.types["A::B::C"].instance_methods).to include(
            m(
                E::Method,
                name: :c1,
                signatures: [],
            ),
            m(
                E::Method,
                name: :c2,
                signatures: [m(
                    E::MethodType,
                    positional_parameters: [],
                    return_type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "String")),
                )],
            )
        )

        expect(subject.types["E"].instance_methods).to include m(
            E::Method,
            name: :e,
            signatures: include(
                m(
                    E::MethodType,
                    positional_parameters: [m(
                        E::PositionalParameter,
                        type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "Object")),
                    )],
                    return_type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "Object")),
                ),
                m(
                    E::MethodType,
                    positional_parameters: [m(
                        E::PositionalParameter,
                        type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "String")),
                    )],
                    return_type: m(E::TypeInstance, type: m(E::PendingDefinedType, path: "String")),
                ),
            ),
        )
    end

    it 'can have acceptance checked' do
        str = subject.resolve_type('String')
        int = subject.resolve_type('Integer')
        num = subject.resolve_type('Numeric')
        obj = subject.resolve_type('Object')

        # Strings
        expect(str.accepts?(str)).to eq 0
        expect(obj.accepts?(str)).to eq 1
        expect(str.accepts?(obj)).to eq false

        # Integers
        expect(int.accepts?(int)).to eq 0
        expect(num.accepts?(int)).to eq 1
        expect(obj.accepts?(int)).to eq 2
        expect(int.accepts?(num)).to eq false
        expect(int.accepts?(str)).to eq false

        # Untyped and void
        expect(E::UntypedType.new.accepts?(int)).to eq 1
        expect(E::VoidType.new.accepts?(int)).to eq 1

        # Unions
        int_str = E::UnionType.new([int, str])
        expect(int_str.accepts?(int)).to eq 1
        expect(int_str.accepts?(str)).to eq 1
        expect(int_str.accepts?(num)).to eq false
        expect(int_str.accepts?(obj)).to eq false

        num_str = E::UnionType.new([num, str])
        expect(num_str.accepts?(int)).to eq 2
        expect(num_str.accepts?(str)).to eq 1
        expect(num_str.accepts?(num)).to eq 1
        expect(num_str.accepts?(obj)).to eq false

        int_num_str = E::UnionType.new([int_str, num_str]).simplify
        expect(int_num_str.accepts?(int)).to eq 1
        expect(int_num_str.accepts?(str)).to eq 1
        expect(int_num_str.accepts?(num)).to eq 1
        expect(int_num_str.accepts?(obj)).to eq false
    end

    it 'can resolve signatures on methods based on arguments' do
        mt = ->s do
            m = Houndstooth::Environment::TypeParser.parse_method_type(s)
            m.resolve_all_pending_types(subject, context: nil)
            m
        end
        t = ->s{ subject.resolve_type(s).instantiate }

        foo = E::Method.new(:foo, [
            mt.('(String, Numeric) -> Numeric'),
            mt.('(String, Integer) -> Integer'),
            mt.('(String) -> String'),
        ])
        inst = E::TypeInstance.new(nil)

        # Exact signature matches
        expect(foo.resolve_matching_signature(inst, [
            [I::PositionalArgument.new(nil), t.('String')],
            [I::PositionalArgument.new(nil), t.('Numeric')],
        ])).to eq foo.signatures[0]

        expect(foo.resolve_matching_signature(inst, [
            [I::PositionalArgument.new(nil), t.('String')],
            [I::PositionalArgument.new(nil), t.('Integer')],
        ])).to eq foo.signatures[1]

        expect(foo.resolve_matching_signature(inst, [
            [I::PositionalArgument.new(nil), t.('String')],
        ])).to eq foo.signatures[2]

        # Variant match (Numeric accepts Float)
        expect(foo.resolve_matching_signature(inst, [
            [I::PositionalArgument.new(nil), t.('String')],
            [I::PositionalArgument.new(nil), t.('Float')],
        ])).to eq foo.signatures[0]

        # Invalid, too many arguments
        expect(foo.resolve_matching_signature(inst, [
            [I::PositionalArgument.new(nil), t.('String')],
            [I::PositionalArgument.new(nil), t.('Float')],
            [I::PositionalArgument.new(nil), t.('Integer')],
        ])).to eq nil

        # Invalid, too few arguments
        expect(foo.resolve_matching_signature(inst, [])).to eq nil

        # Invalid, incorrect argument type
        expect(foo.resolve_matching_signature(inst, [
            [I::PositionalArgument.new(nil), t.('String')],
            [I::PositionalArgument.new(nil), t.('Object')],
        ])).to eq nil
    end

    it 'can be un-eigened' do
        expect(subject.resolve_type('Object').eigen.uneigen).to eq 'Object'
    end

    it 'parses #!const' do
        Houndstooth::Stdlib.add_types(subject)
        meth = subject.resolve_type('Numeric').resolve_instance_method(:+, subject)
        expect(meth.const).to eq :internal
    end
end
