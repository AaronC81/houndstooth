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

        expect(code_to_semantic_node('1..3')).to be_a(RangeLiteral) & have_attributes(
            first: be_a(IntegerLiteral) & have_attributes(value: 1),
            last: be_a(IntegerLiteral) & have_attributes(value: 3),
            inclusive: true,
        )

        expect(code_to_semantic_node('1...3')).to be_a(RangeLiteral) & have_attributes(
            first: be_a(IntegerLiteral) & have_attributes(value: 1),
            last: be_a(IntegerLiteral) & have_attributes(value: 3),
            inclusive: false,
        )

        expect(code_to_semantic_node('1..')).to be_a(RangeLiteral) & have_attributes(
            first: be_a(IntegerLiteral) & have_attributes(value: 1),
            last: be(nil),
            inclusive: true,
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

        expect(code_to_semantic_node('array.filter { |x| x.even? }')).to be_a(Send) & have_attributes(
            target: be_a(Send) & have_attributes(target: nil, method: :array),
            method: :filter,
            positional_arguments: [],
            keyword_arguments: [],

            block: be_a(Block) & have_attributes(
                parameters: be_a(Parameters) & have_attributes(
                    only_proc_parameter: true,
                    positional_parameters: [],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

                body: be_a(Send)
            )
        )

        expect(code_to_semantic_node('array.filter { _1.even? }')).to be_a(Send) & have_attributes(
            target: be_a(Send) & have_attributes(target: nil, method: :array),
            method: :filter,
            positional_arguments: [],
            keyword_arguments: [],

            block: be_a(Block) & have_attributes(
                parameters: be_a(Parameters) & have_attributes(
                    only_proc_parameter: true,
                    positional_parameters: [],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

                body: be_a(Send)
            )
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

        expect(code_to_semantic_node('array.each_cons(2) { _1 + _2 }')).to be_a(Send) & have_attributes(
            target: be_a(Send) & have_attributes(target: nil, method: :array),
            method: :each_cons,
            positional_arguments: [
                be_a(IntegerLiteral) & have_attributes(value: 2),
            ],
            keyword_arguments: [],

            block: be_a(Block) & have_attributes(
                parameters: be_a(Parameters) & have_attributes(
                    positional_parameters: [:_1, :_2],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

                body: be_a(Send) & have_attributes(
                    target: be_a(LocalVariable) & have_attributes(name: :_1),
                    method: :+,
                    positional_arguments: [
                        be_a(LocalVariable) & have_attributes(name: :_2)
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
                be_a(VariableAssignment) & have_attributes(
                    target: be_a(LocalVariable) & have_attributes(name: :x),
                    value: be_a(IntegerLiteral) & have_attributes(value: 3),
                ),
                be_a(LocalVariable) & have_attributes(name: :x),
            ]
        )
    end

    it 'translates instance, class, and global variables' do
        expect(code_to_semantic_node('@x')).to be_a(InstanceVariable) & have_attributes(name: :@x)
        expect(code_to_semantic_node('@x = 3')).to be_a(VariableAssignment) & have_attributes(
            target: be_a(InstanceVariable) & have_attributes(name: :@x),
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
        )

        expect(code_to_semantic_node('@@x')).to be_a(ClassVariable) & have_attributes(name: :@@x)
        expect(code_to_semantic_node('@@x = 3')).to be_a(VariableAssignment) & have_attributes(
            target: be_a(ClassVariable) & have_attributes(name: :@@x),
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
        )

        expect(code_to_semantic_node('$x')).to be_a(GlobalVariable) & have_attributes(name: :$x)
        expect(code_to_semantic_node('$x = 3')).to be_a(VariableAssignment) & have_attributes(
            target: be_a(GlobalVariable) & have_attributes(name: :$x),
            value: be_a(IntegerLiteral) & have_attributes(value: 3),
        )
    end
    
    it 'translates multiple assignments' do
        expect(code_to_semantic_node('a, @b = 1, 2')).to be_a(MultipleAssignment) & have_attributes(
            targets: [
                be_a(LocalVariable) & have_attributes(name: :a),
                be_a(InstanceVariable) & have_attributes(name: :@b),
            ],
            value: be_a(ArrayLiteral) & have_attributes(nodes: [
                be_a(IntegerLiteral) & have_attributes(value: 1),
                be_a(IntegerLiteral) & have_attributes(value: 2),
            ]),
        )

        expect(code_to_semantic_node('self.a, self.b = 1, 2')).to be_a(MultipleAssignment) & have_attributes(
            targets: [
                be_a(Send) & have_attributes(
                    target: be_a(SelfKeyword),
                    method: :a=,
                    positional_arguments: [
                        be_a(MagicPlaceholder)
                    ]
                ),
                be_a(Send) & have_attributes(
                    target: be_a(SelfKeyword),
                    method: :b=,
                    positional_arguments: [
                        be_a(MagicPlaceholder)
                    ]
                ),
            ],
            value: be_a(ArrayLiteral) & have_attributes(nodes: [
                be_a(IntegerLiteral) & have_attributes(value: 1),
                be_a(IntegerLiteral) & have_attributes(value: 2),
            ]),
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

    it 'translates control flow statements' do
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
                be_a(VariableAssignment) & have_attributes(
                    target: be_a(LocalVariable) & have_attributes(name: :x),
                    value: be_a(Send) & have_attributes(method: :foo),
                ),

                # ___fabricated = x
                be_a(VariableAssignment) & have_attributes(
                    target: be_a(LocalVariable) & have_attributes(fabricated: true),
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

        expect(code_to_semantic_node("while x; y; end")).to be_a(While) & have_attributes(
            condition: be_a(Send) & have_attributes(
                target: nil,
                method: :x,
            ),
            body: be_a(Send) & have_attributes(
                target: nil,
                method: :y,
            )
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

        expect(code_to_semantic_node('a &&= b')).to be_a(BooleanAndAssignment) & have_attributes(
            target: be_a(LocalVariable) & have_attributes(name: :a),
            value: be_a(Send) & have_attributes(target: nil, method: :b),
        )

        expect(code_to_semantic_node('a ||= b')).to be_a(BooleanOrAssignment) & have_attributes(
            target: be_a(LocalVariable) & have_attributes(name: :a),
            value: be_a(Send) & have_attributes(target: nil, method: :b),
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

        expect(code_to_semantic_node('def x(*x, **y, &blk); end')).to be_a(MethodDefinition) & have_attributes(
            name: :x,
            parameters: be_a(Parameters) & have_attributes(
                positional_parameters: [],
                optional_parameters: [],
                rest_parameter: :x,
                rest_keyword_parameter: :y,
                block_parameter: :blk,
            ),
            target: nil,
        )

        expect(code_to_semantic_node('def x(x, ...); y(...); end')).to be_a(MethodDefinition) & have_attributes(
            name: :x,
            parameters: be_a(Parameters) & have_attributes(
                positional_parameters: [:x],
                optional_parameters: [],
                has_forward_parameter: true,
            ),
            target: nil,
            body: be_a(Send) & have_attributes(
                target: nil,
                method: :y,
                positional_arguments: [
                    be_a(ForwardedArguments),
                ]
            )
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

    it 'translates aliases' do
        expect(code_to_semantic_node('alias x y')).to be_a(Alias) & have_attributes(
            from: be_a(SymbolLiteral) & have_attributes(components: ['x']),
            from: be_a(SymbolLiteral) & have_attributes(components: ['y']),
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
                be_a(VariableAssignment) & have_attributes(target: be_a(LocalVariable)),
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

    it 'matches comments to translated nodes' do
        expect(code_to_semantic_node("
            # Hello
            puts 'something'

            # Hello again
            puts 'something else'

            # Outer
            func(
                # Inner 1
                a(b, c, d),
                # Inner 2
                e(f, g),
            )
        ")).to be_a(Body) & have_attributes(
            nodes: [
                be_a(Send) & have_attributes(
                    target: nil,
                    method: :puts,

                    comments: [
                        be_a(Parser::Source::Comment) & have_attributes(text: '# Hello')
                    ]
                ),

                be_a(Send) & have_attributes(
                    target: nil,
                    method: :puts,

                    comments: [
                        be_a(Parser::Source::Comment) & have_attributes(text: '# Hello again')
                    ]
                ),

                be_a(Send) & have_attributes(
                    target: nil,
                    method: :func,

                    comments: [
                        be_a(Parser::Source::Comment) & have_attributes(text: '# Outer')
                    ],

                    positional_arguments: [
                        be_a(Send) & have_attributes(
                            target: nil,
                            method: :a,

                            comments: [
                                be_a(Parser::Source::Comment) & have_attributes(text: '# Inner 1')
                            ]
                        ),
                        be_a(Send) & have_attributes(
                            target: nil,
                            method: :e,

                            comments: [
                                be_a(Parser::Source::Comment) & have_attributes(text: '# Inner 2')
                            ]
                        )
                    ]
                ),
            ]
        )

        expect(code_to_semantic_node("
            # Comment
            a.b.c
        ")).to be_a(Send) & have_attributes(
            target: be_a(Send) & have_attributes(
                target: be_a(Send) & have_attributes(
                    target: nil,
                    method: :a,

                    comments: [
                        have_attributes(text: '# Comment')
                    ]
                ),
                method: :b,
            ),
            method: :c,
        )

        expect(code_to_semantic_node("
            # A
            a   
            # B
                .b
            # C
                .c
        ")).to be_a(Send) & have_attributes(
            target: be_a(Send) & have_attributes(
                target: be_a(Send) & have_attributes(
                    target: nil,
                    method: :a,
                    comments: [have_attributes(text: '# A')],
                ),
                method: :b,
                comments: [have_attributes(text: '# B')],
            ),
            method: :c,
            comments: [have_attributes(text: '# C')],
        )

        expect(code_to_semantic_node("
            # A module.
            module M
                # A class.
                class C1
                    # A method.
                    # Returns a string.
                    def x
                        'hello'
                    end

                    # Another method.
                    def y(a, b)
                        a * b
                    end
                end

                # Another class.
                class C2
                    # A class method.
                    def self.z
                        true
                    end
                end
            end
        ")).to be_a(ModuleDefinition) & have_attributes(
            name: have_attributes(name: :M),
            comments: [have_attributes(text: "# A module.")],

            body: be_a(Body) & have_attributes(
                nodes: [
                    be_a(ClassDefinition) & have_attributes(
                        name: have_attributes(name: :C1),
                        comments: [have_attributes(text: "# A class.")],

                        body: be_a(Body) & have_attributes(
                            nodes: [
                                be_a(MethodDefinition) & have_attributes(
                                    name: :x,
                                    comments: [
                                        have_attributes(text: "# A method."),
                                        have_attributes(text: "# Returns a string."),
                                    ],
                                ),
                                be_a(MethodDefinition) & have_attributes(
                                    name: :y,
                                    comments: [
                                        have_attributes(text: "# Another method."),
                                    ],
                                ),
                            ],
                        ),
                    ),
                    be_a(ClassDefinition) & have_attributes(
                        name: have_attributes(name: :C2),
                        comments: [have_attributes(text: "# Another class.")],

                        body: be_a(MethodDefinition) & have_attributes(
                            name: :z,
                            comments: [
                                have_attributes(text: "# A class method."),
                            ],
                        ),
                    ),
                ]
            ),
        )
    end

    it 'translates splats' do
        expect(code_to_semantic_node("a = *b")).to be_a(VariableAssignment) & have_attributes(
            target: be_a(LocalVariable) & have_attributes(name: :a),
            value: be_a(ArrayLiteral) & have_attributes(
                nodes: [
                    be_a(Splat) & have_attributes(
                        value: be_a(Send) & have_attributes(method: :b)
                    )
                ]
            )
        )
    end

    it 'translates defined? checks' do
        expect(code_to_semantic_node("defined? a")).to be_a(IsDefined) & have_attributes(
            value: be_a(Send) & have_attributes(method: :a),
        )
    end
end
