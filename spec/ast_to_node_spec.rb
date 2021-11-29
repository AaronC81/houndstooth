RSpec.describe 'AST to SemanticNode' do
    it 'translates literals' do
        expect(code_to_semantic_node('1')).to be_a(IntegerLiteral) & have_attributes(value: 1)

        expect(code_to_semantic_node('"hello"')).to be_a(StringLiteral) & have_attributes(
            components: ['hello']
        )

        expect(code_to_semantic_node('"My name is: #{name}!"')).to be_a(StringLiteral) & have_attributes(
            components: [
                'My name is: ',
                be_a(Send) & have_attributes(target: nil, method: :name),
                '!',
            ]
        )

        expect(code_to_semantic_node(':foo')).to be_a(SymbolLiteral) & have_attributes(
            components: ['foo']
        )

        expect(code_to_semantic_node(':"#{name}="')).to be_a(SymbolLiteral) & have_attributes(
            components: [
                be_a(Send) & have_attributes(target: nil, method: :name),
                '=',
            ]
        )
    end

    it 'translates sends' do
        expect(code_to_semantic_node('foo')).to be_a(Send) & have_attributes(
            target: nil,
            method: :foo,
            positional_arguments: [],
            keyword_arguments: [],
            block: nil,
        )

        expect(code_to_semantic_node('Math.add(1, 2, 3)')).to be_a(Send) & have_attributes(
            target: be_a(Constant) & have_attributes(target: nil, name: :Math),
            method: :add,
            positional_arguments: [
                be_a(IntegerLiteral) & have_attributes(value: 1),
                be_a(IntegerLiteral) & have_attributes(value: 2),
                be_a(IntegerLiteral) & have_attributes(value: 3),
            ],
            keyword_arguments: [],
            block: nil,
        )

        expect(code_to_semantic_node('Factory.new(:Person, name: "Aaron", age: 21)')).to be_a(Send) & have_attributes(
            target: be_a(Constant) & have_attributes(target: nil, name: :Factory),
            method: :new,
            positional_arguments: [
                be_a(SymbolLiteral) & have_attributes(components: ['Person']),
            ],
            keyword_arguments: include(
                be_a(SymbolLiteral) & have_attributes(components: ['name']) =>
                    be_a(StringLiteral) & have_attributes(components: ['Aaron']),

                be_a(SymbolLiteral) & have_attributes(components: ['age']) =>
                    be_a(IntegerLiteral) & have_attributes(value: 21),
            ),
            block: nil,
        )

        expect(code_to_semantic_node('array.each_cons(2) { |a, b| a + b }')).to be_a(Send) & have_attributes(
            target: be_a(Send) & have_attributes(target: nil, method: :array),
            method: :each_cons,
            positional_arguments: [
                be_a(IntegerLiteral) & have_attributes(value: 2),
            ],
            keyword_arguments: [],

            block: be_a(Block) & have_attributes(
                positional_parameters: [:a, :b],
                optional_parameters: [],
                keyword_parameters: [],
                optional_keyword_parameters: [],

                body: be_a(Send) & have_attributes(
                    target: be_a(LocalVariable) & have_attributes(name: :a),
                    method: :+,
                    positional_arguments: [
                        be_a(LocalVariable) & have_attributes(name: :b)
                    ],
                )
            )
        )

        expect(code_to_semantic_node('x { |a, b = 3, *e, c:, d: 4, **f| a + b + c + d }')).to be_a(Send) & have_attributes(
            target: nil,
            method: :x,
            positional_arguments: [],
            keyword_arguments: [],

            block: be_a(Block) & have_attributes(
                positional_parameters: [:a],
                optional_parameters: [[:b, be_a(IntegerLiteral) & have_attributes(value: 3)]],
                keyword_parameters: [:c],
                optional_keyword_parameters: [[:d, be_a(IntegerLiteral) & have_attributes(value: 4)]],
                rest_parameter: :e,
                rest_keyword_parameter: :f,

                body: be_a(Send) & have_attributes(
                    target: be_a(Send) & have_attributes(
                        target: be_a(Send) & have_attributes(
                            target: be_a(LocalVariable) & have_attributes(name: :a),
                            method: :+,
                            positional_arguments: [be_a(LocalVariable) & have_attributes(name: :b)],
                        ),
                        method: :+,
                        positional_arguments: [be_a(LocalVariable) & have_attributes(name: :c)],
                    ),
                    method: :+,
                    positional_arguments: [be_a(LocalVariable) & have_attributes(name: :d)],
                )
            )
        )
    end

    it 'translates local variables' do
        expect(code_to_semantic_node('x = 3; x')).to be_a(Body) & have_attributes(
            nodes: [
                be_a(LocalVariableAssignment) & have_attributes(
                    name: :x,
                    value: be_a(IntegerLiteral) & have_attributes(value: 3),
                ),
                be_a(LocalVariable) & have_attributes(name: :x),
            ]
        )
    end

    it 'translates constants' do
        expect(code_to_semantic_node('X')).to be_a(Constant) & have_attributes(name: :X)

        expect(code_to_semantic_node('X::Y::Z')).to be_a(Constant) & have_attributes(
            target: be_a(Constant) & have_attributes(
                target: be_a(Constant) & have_attributes(name: :X),
                name: :Y,
            ),
            name: :Z,
        )

        expect(code_to_semantic_node('lookup_class(:Math)::PI')).to be_a(Constant) & have_attributes(
            target: be_a(Send) & have_attributes(
                target: nil,
                method: :lookup_class,
                positional_arguments: [
                    be_a(SymbolLiteral) & have_attributes(components: ['Math'])
                ],
            ),
            name: :PI,
        )

        expect(code_to_semantic_node('::X::Y::Z')).to be_a(Constant) & have_attributes(            
            target: be_a(Constant) & have_attributes(
                target: be_a(Constant) & have_attributes(
                    target: be_a(ConstantBase),
                    name: :X,
                ),
                name: :Y,
            ),
            name: :Z,
        )
    end
end
