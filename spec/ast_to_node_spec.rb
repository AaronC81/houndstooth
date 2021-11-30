include TypeChecker::SemanticNode

RSpec.describe 'AST to SemanticNode' do
    it 'translates literals' do
        expect(code_to_semantic_node('1')).to be_a(IntegerLiteral) & have_attributes(value: 1)

        expect(code_to_semantic_node('3.0')).to be_a(FloatLiteral) & have_attributes(value: 3.0)
        expect(code_to_semantic_node('3.14')).to be_a(FloatLiteral) & have_attributes(value: 3.14)
        expect(code_to_semantic_node('3e2')).to be_a(FloatLiteral) & have_attributes(value: 300.0)

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

    it 'translates compound literals' do
        # TODO: splats

        expect(code_to_semantic_node('[]')).to be_a(ArrayLiteral) & have_attributes(nodes: [])

        expect(code_to_semantic_node('[1, 2, 3]')).to be_a(ArrayLiteral) & have_attributes(
            nodes: [
                be_a(IntegerLiteral) & have_attributes(value: 1),
                be_a(IntegerLiteral) & have_attributes(value: 2),
                be_a(IntegerLiteral) & have_attributes(value: 3),
            ]
        )

        expect(code_to_semantic_node('{}')).to be_a(HashLiteral) & have_attributes(pairs: [])

        expect(code_to_semantic_node('{a: 3, "b" => 4}')).to be_a(HashLiteral) & have_attributes(
            pairs: [
                [
                    be_a(SymbolLiteral) & have_attributes(components: ['a']),
                    be_a(IntegerLiteral) & have_attributes(value: 3),
                ],
                [
                    be_a(StringLiteral) & have_attributes(components: ['b']),
                    be_a(IntegerLiteral) & have_attributes(value: 4),
                ],
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
                parameters: be_a(Parameters) & have_attributes(
                    positional_parameters: [:a, :b],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

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
                parameters: be_a(Parameters) & have_attributes(
                    positional_parameters: [:a],
                    optional_parameters: [[:b, be_a(IntegerLiteral) & have_attributes(value: 3)]],
                    keyword_parameters: [:c],
                    optional_keyword_parameters: [[:d, be_a(IntegerLiteral) & have_attributes(value: 4)]],
                    rest_parameter: :e,
                    rest_keyword_parameter: :f,
                ),

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

    it 'translates instance, class, and global variables' do
        expect(code_to_semantic_node('@x')).to be_a(InstanceVariable) & have_attributes(name: :@x)
        expect(code_to_semantic_node('@x = 3')).to be_a(InstanceVariableAssignment) & have_attributes(
            name: :@x,
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
        )

        expect(code_to_semantic_node('@@x')).to be_a(ClassVariable) & have_attributes(name: :@@x)
        expect(code_to_semantic_node('@@x = 3')).to be_a(ClassVariableAssignment) & have_attributes(
            name: :@@x,
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
        )

        expect(code_to_semantic_node('$x')).to be_a(GlobalVariable) & have_attributes(name: :$x)
        expect(code_to_semantic_node('$x = 3')).to be_a(GlobalVariableAssignment) & have_attributes(
            name: :$x,
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
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

        expect(code_to_semantic_node('X = 3')).to be_a(ConstantAssignment) & have_attributes(
            target: nil,
            name: :X,
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
        )

        expect(code_to_semantic_node('X::Y = 3')).to be_a(ConstantAssignment) & have_attributes(
            target: be_a(Constant) & have_attributes(name: :X),
            name: :Y,
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
        )
    end

    it 'translates keywords' do
        expect(code_to_semantic_node('true')).to be_a(TrueKeyword)
        expect(code_to_semantic_node('false')).to be_a(FalseKeyword)
        expect(code_to_semantic_node('self')).to be_a(SelfKeyword)
        expect(code_to_semantic_node('nil')).to be_a(NilKeyword)
    end

    it 'translates conditionals' do
        expect(code_to_semantic_node('if foo; bar; end')).to be_a(Conditional) & have_attributes(
            condition: be_a(Send) & have_attributes(
                target: nil,
                method: :foo,
            ),
            true_branch: be_a(Send) & have_attributes(
                target: nil,
                method: :bar,
            ),
            false_branch: nil,
        )

        expect(code_to_semantic_node('if foo; bar; else; baz; end')).to be_a(Conditional) & have_attributes(
            condition: be_a(Send) & have_attributes(
                target: nil,
                method: :foo,
            ),
            true_branch: be_a(Send) & have_attributes(
                target: nil,
                method: :bar,
            ),
            false_branch: be_a(Send) & have_attributes(
                target: nil,
                method: :baz,
            ),
        )

        expect(code_to_semantic_node('foo ? bar : baz')).to be_a(Conditional) & have_attributes(
            condition: be_a(Send) & have_attributes(
                target: nil,
                method: :foo,
            ),
            true_branch: be_a(Send) & have_attributes(
                target: nil,
                method: :bar,
            ),
            false_branch: be_a(Send) & have_attributes(
                target: nil,
                method: :baz,
            ),
        )

        expect(code_to_semantic_node("
            x = foo(3)
            case x
            when String
                a
            when 3
                b
            else 
                c
            end
        ")).to be_a(Body) & have_attributes(
            nodes: [
                # x = foo(3)
                be_a(LocalVariableAssignment) & have_attributes(
                    name: :x,
                    value: be_a(Send) & have_attributes(method: :foo),
                ),

                # ___fabricated = x
                be_a(LocalVariableAssignment) & have_attributes(
                    value: be_a(LocalVariable) & have_attributes(name: :x),
                ),

                # when String
                be_a(Conditional) & have_attributes(
                    condition: be_a(Send) & have_attributes(
                        target: be_a(Constant) & have_attributes(name: :String),
                        method: :===,
                        positional_arguments: [
                            be_a(LocalVariable) & have_attributes(fabricated: true),
                        ],
                    ),
                    true_branch: be_a(Send) & have_attributes(method: :a),

                    # when 3
                    false_branch: be_a(Conditional) & have_attributes(
                        condition: be_a(Send) & have_attributes(
                            target: be_a(IntegerLiteral) & have_attributes(value: 3),
                            method: :===,
                            positional_arguments: [
                                be_a(LocalVariable) & have_attributes(fabricated: true),
                            ],
                        ),
                        true_branch: be_a(Send) & have_attributes(method: :b),

                        # else
                        false_branch: be_a(Send) & have_attributes(method: :c),
                    )
                )
            ]
        )
    end

    it 'translates boolean operators' do
        expect(code_to_semantic_node('a && b')).to be_a(BooleanAnd) & have_attributes(
            left: be_a(Send) & have_attributes(target: nil, method: :a),
            right: be_a(Send) & have_attributes(target: nil, method: :b),
        )

        expect(code_to_semantic_node('a || b')).to be_a(BooleanOr) & have_attributes(
            left: be_a(Send) & have_attributes(target: nil, method: :a),
            right: be_a(Send) & have_attributes(target: nil, method: :b),
        )
    end

    it 'translates method definitions' do
        expect(code_to_semantic_node('def x; end')).to be_a(MethodDefinition) & have_attributes(
            name: :x,
            parameters: be_a(Parameters) & have_attributes(
                positional_parameters: [],
                optional_parameters: [],
            ),
            target: nil,
            body: nil,
        )

        expect(code_to_semantic_node('def add(x, y = 1); x + y; end')).to be_a(MethodDefinition) & have_attributes(
            name: :add,
            parameters: be_a(Parameters) & have_attributes(
                positional_parameters: [:x],
                optional_parameters: [[:y, be_a(IntegerLiteral)]],
            ),
            target: nil,
            body: be_a(Send) & have_attributes(
                target: be_a(LocalVariable) & have_attributes(name: :x),
                method: :+,
                positional_arguments: [
                    be_a(LocalVariable) & have_attributes(name: :y),
                ]
            ),
        )

        expect(code_to_semantic_node('def self.magic; 42; end')).to be_a(MethodDefinition) & have_attributes(
            name: :magic,
            target: be_a(SelfKeyword),
            body: be_a(IntegerLiteral) & have_attributes(value: 42),
        )

        expect(code_to_semantic_node('def x.double; end')).to be_a(MethodDefinition) & have_attributes(
            name: :double,
            target: be_a(Send) & have_attributes(target: nil, method: :x),
            body: nil,
        )
    end

    it 'translates class definitions and singleton class accesses' do
        expect(code_to_semantic_node('class X; end')).to be_a(ClassDefinition) & have_attributes(
            name: be_a(Constant) & have_attributes(
                target: nil,
                name: :X,
            ),
            superclass: nil,
            body: nil,
        )

        expect(code_to_semantic_node("
            class X < Y
                def foo
                end

                def bar
                end
            end
        ")).to be_a(ClassDefinition) & have_attributes(
            name: be_a(Constant) & have_attributes(
                target: nil,
                name: :X,
            ),
            superclass: be_a(Constant) & have_attributes(
                target: nil,
                name: :Y,
            ),
            body: be_a(Body) & have_attributes(
                nodes: [
                    be_a(MethodDefinition) & have_attributes(target: nil, name: :foo, body: nil),
                    be_a(MethodDefinition) & have_attributes(target: nil, name: :bar, body: nil),
                ]
            ),
        )

        expect(code_to_semantic_node("
            class X
                def foo
                end

                class << self
                    def bar
                    end
                end
            end
        ")).to be_a(ClassDefinition) & have_attributes(
            name: be_a(Constant) & have_attributes(
                target: nil,
                name: :X,
            ),
            superclass: nil,
            body: be_a(Body) & have_attributes(
                nodes: [
                    be_a(MethodDefinition) & have_attributes(target: nil, name: :foo, body: nil),
                    be_a(SingletonClass) & have_attributes(
                        target: be_a(SelfKeyword),
                        body: be_a(MethodDefinition) & have_attributes(target: nil, name: :bar, body: nil),
                    )
                ]
            ),
        )

        expect(code_to_semantic_node("
            x = Object.new
            class << x
            end
        ")).to be_a(Body) & have_attributes(
            nodes: [
                be_a(LocalVariableAssignment) & have_attributes(name: :x),
                be_a(SingletonClass) & have_attributes(
                    target: be_a(LocalVariable) & have_attributes(name: :x),
                    body: nil,
                )
            ]
        )
    end

    it 'translates module definitions' do
        expect(code_to_semantic_node("
            module X
                def foo
                end

                def bar
                end
            end
        ")).to be_a(ModuleDefinition) & have_attributes(
            name: be_a(Constant) & have_attributes(
                target: nil,
                name: :X,
            ),
            body: be_a(Body) & have_attributes(
                nodes: [
                    be_a(MethodDefinition) & have_attributes(target: nil, name: :foo, body: nil),
                    be_a(MethodDefinition) & have_attributes(target: nil, name: :bar, body: nil),
                ]
            ),
        )
    end
end
