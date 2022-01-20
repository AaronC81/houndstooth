include TypeChecker::SemanticNode

RSpec.describe 'AST to SemanticNode' do
    it 'translates literals' do
        expect(code_to_semantic_node('1')).to m(IntegerLiteral, value: 1)

        expect(code_to_semantic_node('3.0')).to m(FloatLiteral, value: 3.0)
        expect(code_to_semantic_node('3.14')).to m(FloatLiteral, value: 3.14)
        expect(code_to_semantic_node('3e2')).to m(FloatLiteral, value: 300.0)

        expect(code_to_semantic_node('"hello"')).to m(StringLiteral, components: ['hello'])

        expect(code_to_semantic_node('"My name is: #{name}!"')).to m(StringLiteral, components: [
            'My name is: ',
            m(Send, target: nil, method: :name),
            '!',
        ])

        expect(code_to_semantic_node(':foo')).to m(SymbolLiteral, components: ['foo'])

        expect(code_to_semantic_node(':"#{name}="')).to m(SymbolLiteral, components: [
            m(Send, target: nil, method: :name),
            '=',
        ])

        expect(code_to_semantic_node('1..3')).to m(RangeLiteral,
            first: m(IntegerLiteral, value: 1),
            last: m(IntegerLiteral, value: 3),
            inclusive: true,
        )

        expect(code_to_semantic_node('1...3')).to m(RangeLiteral,
            first: m(IntegerLiteral, value: 1),
            last: m(IntegerLiteral, value: 3),
            inclusive: false,
        )

        expect(code_to_semantic_node('1..')).to m(RangeLiteral,
            first: m(IntegerLiteral, value: 1),
            last: be(nil),
            inclusive: true,
        )
    end

    it 'translates compound literals' do
        # TODO: splats

        expect(code_to_semantic_node('[]')).to m(ArrayLiteral, nodes: [])

        expect(code_to_semantic_node('[1, 2, 3]')).to m(ArrayLiteral, nodes: [
            m(IntegerLiteral, value: 1),
            m(IntegerLiteral, value: 2),
            m(IntegerLiteral, value: 3),
        ])

        expect(code_to_semantic_node('{}')).to m(HashLiteral, pairs: [])

        expect(code_to_semantic_node('{a: 3, "b" => 4}')).to m(HashLiteral, pairs: [
            [
                m(SymbolLiteral, components: ['a']),
                m(IntegerLiteral, value: 3),
            ],
            [
                m(StringLiteral, components: ['b']),
                m(IntegerLiteral, value: 4),
            ],
        ])
    end

    it 'translates sends' do
        expect(code_to_semantic_node('foo')).to m(Send,
            target: nil,
            method: :foo,
            positional_arguments: [],
            keyword_arguments: [],
            block: nil,
        )

        expect(code_to_semantic_node('Math.add(1, 2, 3)')).to m(Send,
            target: m(Constant, target: nil, name: :Math),
            method: :add,
            positional_arguments: [
                m(IntegerLiteral, value: 1),
                m(IntegerLiteral, value: 2),
                m(IntegerLiteral, value: 3),
            ],
            keyword_arguments: [],
            block: nil,
        )

        expect(code_to_semantic_node('Factory.new(:Person, name: "Aaron", age: 21)')).to m(Send,
            target: m(Constant, target: nil, name: :Factory),
            method: :new,
            positional_arguments: [
                m(SymbolLiteral, components: ['Person']),
            ],
            keyword_arguments: include(
                m(SymbolLiteral, components: ['name']) =>
                    m(StringLiteral, components: ['Aaron']),
                m(SymbolLiteral, components: ['age']) =>
                    m(IntegerLiteral, value: 21),
            ),
            block: nil,
        )

        expect(code_to_semantic_node('array.filter { |x| x.even? }')).to m(Send,
            target: m(Send, target: nil, method: :array),
            method: :filter,
            positional_arguments: [],
            keyword_arguments: [],

            block: m(Block,
                parameters: m(Parameters,
                    only_proc_parameter: true,
                    positional_parameters: [],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

                body: m(Send)
            )
        )

        expect(code_to_semantic_node('array.filter { _1.even? }')).to m(Send,
            target: m(Send, target: nil, method: :array),
            method: :filter,
            positional_arguments: [],
            keyword_arguments: [],

            block: m(Block,
                parameters: m(Parameters,
                    only_proc_parameter: true,
                    positional_parameters: [],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

                body: be_a(Send)
            )
        )

        expect(code_to_semantic_node('array.each_cons(2) { |a, b| a + b }')).to m(Send,
            target: m(Send, target: nil, method: :array),
            method: :each_cons,
            positional_arguments: [
                m(IntegerLiteral, value: 2),
            ],
            keyword_arguments: [],

            block: m(Block,
                parameters: m(Parameters,
                    positional_parameters: [:a, :b],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

                body: m(Send,
                    target: m(LocalVariable, name: :a),
                    method: :+,
                    positional_arguments: [
                        m(LocalVariable, name: :b)
                    ],
                )
            )
        )

        expect(code_to_semantic_node('array.each_cons(2) { _1 + _2 }')).to m(Send,
            target: m(Send, target: nil, method: :array),
            method: :each_cons,
            positional_arguments: [m(IntegerLiteral, value: 2)],
            keyword_arguments: [],

            block: m(Block,
                parameters: m(Parameters,
                    positional_parameters: [:_1, :_2],
                    optional_parameters: [],
                    keyword_parameters: [],
                    optional_keyword_parameters: [],
                ),

                body: m(Send,
                    target: m(LocalVariable, name: :_1),
                    method: :+,
                    positional_arguments: [
                        m(LocalVariable, name: :_2)
                    ],
                )
            )
        )

        expect(code_to_semantic_node('x { |a, b = 3, *e, c:, d: 4, **f| a + b + c + d }')).to m(Send,
            target: nil,
            method: :x,
            positional_arguments: [],
            keyword_arguments: [],

            block: m(Block,
                parameters: m(Parameters,
                    positional_parameters: [:a],
                    optional_parameters: [[:b, m(IntegerLiteral, value: 3)]],
                    keyword_parameters: [:c],
                    optional_keyword_parameters: [[:d, m(IntegerLiteral, value: 4)]],
                    rest_parameter: :e,
                    rest_keyword_parameter: :f,
                ),

                body: m(Send,
                    target: m(Send,
                        target: m(Send,
                            target: m(LocalVariable, name: :a),
                            method: :+,
                            positional_arguments: [m(LocalVariable, name: :b)],
                        ),
                        method: :+,
                        positional_arguments: [m(LocalVariable, name: :c)],
                    ),
                    method: :+,
                    positional_arguments: [m(LocalVariable, name: :d)],
                )
            )
        )

        expect(code_to_semantic_node('x&.y')).to m(Send,
            target: m(Send, target: nil, method: :x),
            method: :y,
            safe_navigation: true,
        )
    end

    it 'translates local variables' do
        expect(code_to_semantic_node('x = 3; x')).to m(Body,
            nodes: [
                m(VariableAssignment,
                    target: m(LocalVariable, name: :x),
                    value: m(IntegerLiteral, value: 3),
                ),
                m(LocalVariable, name: :x),
            ]
        )
    end

    it 'translates instance, class, and global variables' do
        expect(code_to_semantic_node('@x')).to m(InstanceVariable, name: :@x)
        expect(code_to_semantic_node('@x = 3')).to m(VariableAssignment,
            target: m(InstanceVariable, name: :@x),
            value: m(IntegerLiteral, value: 3),
        )

        expect(code_to_semantic_node('@@x')).to m(ClassVariable, name: :@@x)
        expect(code_to_semantic_node('@@x = 3')).to m(VariableAssignment,
            target: m(ClassVariable, name: :@@x),
            value: m(IntegerLiteral, value: 3),
        )

        expect(code_to_semantic_node('$x')).to m(GlobalVariable, name: :$x)
        expect(code_to_semantic_node('$x = 3')).to m(VariableAssignment,
            target: m(GlobalVariable, name: :$x),
            value: m(IntegerLiteral, value: 3),
        )
    end
    
    it 'translates multiple assignments' do
        expect(code_to_semantic_node('a, @b = 1, 2')).to m(MultipleAssignment,
            targets: [
                m(LocalVariable, name: :a),
                m(InstanceVariable, name: :@b),
            ],
            value: m(ArrayLiteral, nodes: [
                m(IntegerLiteral, value: 1),
                m(IntegerLiteral, value: 2),
            ]),
        )

        expect(code_to_semantic_node('self.a, self.b = 1, 2')).to m(MultipleAssignment,
            targets: [
                m(Send,
                    target: be_a(SelfKeyword),
                    method: :a=,
                    positional_arguments: [m(MagicPlaceholder)]
                ),
                m(Send,
                    target: be_a(SelfKeyword),
                    method: :b=,
                    positional_arguments: [m(MagicPlaceholder)]
                ),
            ],
            value: m(ArrayLiteral, nodes: [
                m(IntegerLiteral, value: 1),
                m(IntegerLiteral, value: 2),
            ]),
        )
    end

    it 'translates op-assignments' do
        expect(code_to_semantic_node('x = 1; x += 3')).to m(Body,
            nodes: [
                m(VariableAssignment),
                m(VariableAssignment,
                    target: m(LocalVariable, name: :x),
                    value: m(Send,
                        target: m(LocalVariable, name: :x),
                        method: :+,

                        positional_arguments: [m(IntegerLiteral, value: 3)]
                    )
                )
            ]
        )
    end

    it 'translates constants' do
        expect(code_to_semantic_node('X')).to m(Constant, name: :X)

        expect(code_to_semantic_node('X::Y::Z')).to m(Constant,
            target: m(Constant,
                target: m(Constant, name: :X),
                name: :Y,
            ),
            name: :Z,
        )

        expect(code_to_semantic_node('lookup_class(:Math)::PI')).to m(Constant,
            target: m(Send,
                target: nil,
                method: :lookup_class,
                positional_arguments: [
                    m(SymbolLiteral, components: ['Math'])
                ],
            ),
            name: :PI,
        )

        expect(code_to_semantic_node('::X::Y::Z')).to m(Constant,            
            target: m(Constant,
                target: m(Constant,
                    target: be_a(ConstantBase),
                    name: :X,
                ),
                name: :Y,
            ),
            name: :Z,
        )

        expect(code_to_semantic_node('X = 3')).to m(ConstantAssignment,
            target: nil,
            name: :X,
            value: m(IntegerLiteral, value: 3),
        )

        expect(code_to_semantic_node('X::Y = 3')).to m(ConstantAssignment,
            target: m(Constant, name: :X),
            name: :Y,
            value: m(IntegerLiteral, value: 3),
        )
    end

    it 'translates keywords' do
        expect(code_to_semantic_node('true')).to be_a(TrueKeyword)
        expect(code_to_semantic_node('false')).to be_a(FalseKeyword)
        expect(code_to_semantic_node('self')).to be_a(SelfKeyword)
        expect(code_to_semantic_node('nil')).to be_a(NilKeyword)
    end

    it 'translates control flow statements' do
        expect(code_to_semantic_node('if foo; bar; end')).to m(Conditional,
            condition: m(Send,
                target: nil,
                method: :foo,
            ),
            true_branch: m(Send,
                target: nil,
                method: :bar,
            ),
            false_branch: nil,
        )

        expect(code_to_semantic_node('if foo; bar; else; baz; end')).to m(Conditional,
            condition: m(Send,
                target: nil,
                method: :foo,
            ),
            true_branch: m(Send,
                target: nil,
                method: :bar,
            ),
            false_branch: m(Send,
                target: nil,
                method: :baz,
            ),
        )

        expect(code_to_semantic_node('foo ? bar : baz')).to m(Conditional,
            condition: m(Send,
                target: nil,
                method: :foo,
            ),
            true_branch: m(Send,
                target: nil,
                method: :bar,
            ),
            false_branch: m(Send,
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
        ")).to m(Body,
            nodes: [
                # x = foo(3)
                m(VariableAssignment,
                    target: m(LocalVariable, name: :x),
                    value: m(Send, method: :foo),
                ),

                # ___fabricated = x
                m(VariableAssignment,
                    target: m(LocalVariable, fabricated: true),
                    value: m(LocalVariable, name: :x),
                ),

                # when String
                m(Conditional,
                    condition: m(Send,
                        target: m(Constant, name: :String),
                        method: :===,
                        positional_arguments: [
                            m(LocalVariable, fabricated: true),
                        ],
                    ),
                    true_branch: m(Send, method: :a),

                    # when 3
                    false_branch: m(Conditional,
                        condition: m(Send,
                            target: m(IntegerLiteral, value: 3),
                            method: :===,
                            positional_arguments: [
                                m(LocalVariable, fabricated: true),
                            ],
                        ),
                        true_branch: m(Send, method: :b),

                        # else
                        false_branch: m(Send, method: :c),
                    )
                )
            ]
        )

        expect(code_to_semantic_node("while x; y; end")).to m(While,
            condition: m(Send,
                target: nil,
                method: :x,
            ),
            body: m(Send,
                target: nil,
                method: :y,
            )
        )
    end

    it 'translates boolean operators' do
        expect(code_to_semantic_node('a && b')).to m(BooleanAnd,
            left: m(Send, target: nil, method: :a),
            right: m(Send, target: nil, method: :b),
        )

        expect(code_to_semantic_node('a || b')).to m(BooleanOr,
            left: m(Send, target: nil, method: :a),
            right: m(Send, target: nil, method: :b),
        )

        expect(code_to_semantic_node('a &&= b')).to m(BooleanAndAssignment,
            target: m(LocalVariable, name: :a),
            value: m(Send, target: nil, method: :b),
        )

        expect(code_to_semantic_node('a ||= b')).to m(BooleanOrAssignment,
            target: m(LocalVariable, name: :a),
            value: m(Send, target: nil, method: :b),
        )
    end

    it 'translates method definitions' do
        expect(code_to_semantic_node('def x; end')).to m(MethodDefinition,
            name: :x,
            parameters: m(Parameters,
                positional_parameters: [],
                optional_parameters: [],
            ),
            target: nil,
            body: nil,
        )

        expect(code_to_semantic_node('def add(x, y = 1); x + y; end')).to m(MethodDefinition,
            name: :add,
            parameters: m(Parameters,
                positional_parameters: [:x],
                optional_parameters: [[:y, be_a(IntegerLiteral)]],
            ),
            target: nil,
            body: m(Send,
                target: m(LocalVariable, name: :x),
                method: :+,
                positional_arguments: [
                    m(LocalVariable, name: :y),
                ]
            ),
        )

        expect(code_to_semantic_node('def x(*x, **y, &blk); end')).to m(MethodDefinition,
            name: :x,
            parameters: m(Parameters,
                positional_parameters: [],
                optional_parameters: [],
                rest_parameter: :x,
                rest_keyword_parameter: :y,
                block_parameter: :blk,
            ),
            target: nil,
        )

        expect(code_to_semantic_node('def x(x, ...); y(...); end')).to m(MethodDefinition,
            name: :x,
            parameters: m(Parameters,
                positional_parameters: [:x],
                optional_parameters: [],
                has_forward_parameter: true,
            ),
            target: nil,
            body: m(Send,
                target: nil,
                method: :y,
                positional_arguments: [
                    be_a(ForwardedArguments),
                ]
            )
        )

        expect(code_to_semantic_node('def self.magic; 42; end')).to m(MethodDefinition,
            name: :magic,
            target: be_a(SelfKeyword),
            body: m(IntegerLiteral, value: 42),
        )

        expect(code_to_semantic_node('def x.double; end')).to m(MethodDefinition,
            name: :double,
            target: m(Send, target: nil, method: :x),
            body: nil,
        )
    end

    it 'translates aliases' do
        expect(code_to_semantic_node('alias x y')).to m(Alias,
            from: m(SymbolLiteral, components: ['y']),
            to: m(SymbolLiteral, components: ['x']),
        )
    end

    it 'translates class definitions and singleton class accesses' do
        expect(code_to_semantic_node('class X; end')).to m(ClassDefinition,
            name: m(Constant,
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
        ")).to m(ClassDefinition,
            name: m(Constant,
                target: nil,
                name: :X,
            ),
            superclass: m(Constant,
                target: nil,
                name: :Y,
            ),
            body: m(Body,
                nodes: [
                    m(MethodDefinition, target: nil, name: :foo, body: nil),
                    m(MethodDefinition, target: nil, name: :bar, body: nil),
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
        ")).to m(ClassDefinition,
            name: m(Constant,
                target: nil,
                name: :X,
            ),
            superclass: nil,
            body: m(Body,
                nodes: [
                    m(MethodDefinition, target: nil, name: :foo, body: nil),
                    m(SingletonClass,
                        target: be_a(SelfKeyword),
                        body: m(MethodDefinition, target: nil, name: :bar, body: nil),
                    )
                ]
            ),
        )

        expect(code_to_semantic_node("
            x = Object.new
            class << x
            end
        ")).to m(Body,
            nodes: [
                m(VariableAssignment, target: be_a(LocalVariable)),
                m(SingletonClass,
                    target: m(LocalVariable, name: :x),
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
        ")).to m(ModuleDefinition,
            name: m(Constant,
                target: nil,
                name: :X,
            ),
            body: m(Body,
                nodes: [
                    m(MethodDefinition, target: nil, name: :foo, body: nil),
                    m(MethodDefinition, target: nil, name: :bar, body: nil),
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
        ")).to m(Body,
            nodes: [
                m(Send,
                    target: nil,
                    method: :puts,

                    comments: [
                        be_a(Parser::Source::Comment) & have_attributes(text: '# Hello')
                    ]
                ),

                m(Send,
                    target: nil,
                    method: :puts,

                    comments: [
                        be_a(Parser::Source::Comment) & have_attributes(text: '# Hello again')
                    ]
                ),

                m(Send,
                    target: nil,
                    method: :func,

                    comments: [
                        be_a(Parser::Source::Comment) & have_attributes(text: '# Outer')
                    ],

                    positional_arguments: [
                        m(Send,
                            target: nil,
                            method: :a,

                            comments: [
                                be_a(Parser::Source::Comment) & have_attributes(text: '# Inner 1')
                            ]
                        ),
                        m(Send,
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
        ")).to m(Send,
            target: m(Send,
                target: m(Send,
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
        ")).to m(Send,
            target: m(Send,
                target: m(Send,
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
        ")).to m(ModuleDefinition,
            name: have_attributes(name: :M),
            comments: [have_attributes(text: "# A module.")],

            body: m(Body,
                nodes: [
                    m(ClassDefinition,
                        name: have_attributes(name: :C1),
                        comments: [have_attributes(text: "# A class.")],

                        body: m(Body,
                            nodes: [
                                m(MethodDefinition,
                                    name: :x,
                                    comments: [
                                        have_attributes(text: "# A method."),
                                        have_attributes(text: "# Returns a string."),
                                    ],
                                ),
                                m(MethodDefinition,
                                    name: :y,
                                    comments: [
                                        have_attributes(text: "# Another method."),
                                    ],
                                ),
                            ],
                        ),
                    ),
                    m(ClassDefinition,
                        name: have_attributes(name: :C2),
                        comments: [have_attributes(text: "# Another class.")],

                        body: m(MethodDefinition,
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
        expect(code_to_semantic_node("a = *b")).to m(VariableAssignment,
            target: m(LocalVariable, name: :a),
            value: m(ArrayLiteral,
                nodes: [
                    m(Splat,
                        value: m(Send, method: :b)
                    )
                ]
            )
        )
    end

    it 'translates defined? checks' do
        expect(code_to_semantic_node("defined? a")).to m(IsDefined,
            value: m(Send, method: :a),
        )
    end

    it 'translates control-flow expressions such as return' do
        expect(code_to_semantic_node("return")).to m(Return, value: nil)
        expect(code_to_semantic_node("return 3")).to m(Return,
            value: m(IntegerLiteral, value: 3),
        )
        expect(code_to_semantic_node("return 3, 4")).to m(Return,
            value: m(ArrayLiteral,
                nodes: [
                    m(IntegerLiteral, value: 3),
                    m(IntegerLiteral, value: 4),
                ],
            )
        )

        # These need minimal tests because they'll all behave the same, they derive from the same
        # mixin
        expect(code_to_semantic_node("break")).to m(Break, value: nil)
        expect(code_to_semantic_node("next")).to m(Next, value: nil)
    end
end
