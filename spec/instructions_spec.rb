RSpec.describe Houndstooth::Instructions do
    I = Houndstooth::Instructions

    def code_to_block(code)
        block = I::InstructionBlock.new(has_scope: true, parent: nil)
        code_to_semantic_node(code).to_instructions(block)
        block
    end

    it 'can be created from basic literals' do
        # Keywords
        expect(code_to_block("
            true
            false
            nil
            self
        ").instructions).to match_array [
            m(I::LiteralInstruction, value: true),
            m(I::LiteralInstruction, value: false),
            m(I::LiteralInstruction, value: nil),
            m(I::SelfInstruction),
        ]

        # Literals
        expect(code_to_block("
            0
            2.4
            'Hello'
            :hello
        ").instructions).to match_array [
            m(I::LiteralInstruction, value: 0),
            m(I::LiteralInstruction, value: 2.4),
            m(I::LiteralInstruction, value: "Hello"),
            m(I::LiteralInstruction, value: :hello),
        ]

        # Interpolated string
        string_interp = code_to_block("\"2 is \#{2}...\"").instructions
        expect(string_interp).to match_array [
            m(I::LiteralInstruction, value: "2 is "),
            m(I::LiteralInstruction, value: 2),
            m(I::ToStringInstruction, target: string_interp[1].result),
            m(I::LiteralInstruction, value: "..."),
            m(I::SendInstruction,
                target: string_interp[0].result,
                method_name: :+,
                positional_arguments: [string_interp[2].result],
            ),
            m(I::SendInstruction,
                target: string_interp[4].result,
                method_name: :+,
                positional_arguments: [string_interp[3].result],
            ),
        ]

        # Interpolated symbol
        sym_interp = code_to_block(":\"2 is \#{2}...\"").instructions
        expect(sym_interp).to match_array [
            m(I::LiteralInstruction, value: "2 is "),
            m(I::LiteralInstruction, value: 2),
            m(I::ToStringInstruction, target: sym_interp[1].result),
            m(I::LiteralInstruction, value: "..."),
            m(I::SendInstruction,
                target: sym_interp[0].result,
                method_name: :+,
                positional_arguments: [sym_interp[2].result],
            ),
            m(I::SendInstruction,
                target: sym_interp[4].result,
                method_name: :+,
                positional_arguments: [sym_interp[3].result],
            ),
            m(I::SendInstruction,
                target: sym_interp[5].result,
                method_name: :to_sym,
            )
        ]
    end

    it 'can be created from conditionals' do
        ins = code_to_block("if true; 2; end").instructions
        expect(ins).to match_array [
            m(I::LiteralInstruction, value: true),
            m(I::ConditionalInstruction,
                condition: ins[0].result,
                true_branch: m(I::InstructionBlock, instructions: [
                    m(I::LiteralInstruction, value: 2),
                ]),
                false_branch: m(I::InstructionBlock, instructions: [
                    m(I::LiteralInstruction, value: nil),
                ]),
            )
        ]

        # elsif always become an else with an if inside, so I'm not going to write a test for that

        ins = code_to_block("true ? 2 : 4").instructions
        expect(ins).to match_array [
            m(I::LiteralInstruction, value: true),
            m(I::ConditionalInstruction,
                condition: ins[0].result,
                true_branch: m(I::InstructionBlock, instructions: [
                    m(I::LiteralInstruction, value: 2),
                ]),
                false_branch: m(I::InstructionBlock, instructions: [
                    m(I::LiteralInstruction, value: 4),
                ]),
            )
        ]
    end 

    it 'can be created from method calls' do
        # Implicit `self` target
        ins = code_to_block("a").instructions
        expect(ins).to match_array [
            m(I::SelfInstruction),
            m(I::SendInstruction,
                target: ins[0].result,
                method_name: :a,
                positional_arguments: [],
                keyword_arguments: {},
            ),
        ]

        # Explicit target
        ins = code_to_block("-3.abs").instructions
        expect(ins).to match_array [
            m(I::LiteralInstruction, value: -3),
            m(I::SendInstruction,
                target: ins[0].result,
                method_name: :abs,
                positional_arguments: [],
                keyword_arguments: {},
            ),
        ]

        # Arguments
        ins = code_to_block("combine(1, 2, 3, strategy: :add)").instructions
        expect(ins).to match_array [
            # Target
            m(I::SelfInstruction),

            # Arguments
            m(I::LiteralInstruction, value: 1),
            m(I::LiteralInstruction, value: 2),
            m(I::LiteralInstruction, value: 3),
            m(I::LiteralInstruction, value: :add),

            # Send
            m(I::SendInstruction,
                target: ins[0].result,
                method_name: :combine,
                positional_arguments: [
                    ins[1].result,
                    ins[2].result,
                    ins[3].result,
                ],
                keyword_arguments: {
                    "strategy" => ins[4].result,
                },
            ),
        ]

        # Safe navigation
        ins = code_to_block("a&.b").instructions
        expect(ins).to match_array [
            # Target
            m(I::SelfInstruction),
            m(I::SendInstruction,
                target: ins[0].result,
                method_name: :a,
            ),

            # Safe navigation
            m(I::SendInstruction,
                target: ins[1].result,
                method_name: :nil?,
            ),
            m(I::ConditionalInstruction,
                condition: ins[2].result,
                true_branch: m(I::InstructionBlock, instructions: [
                    m(I::LiteralInstruction, value: nil),
                ]),
                false_branch: m(I::InstructionBlock, instructions: [
                    # Send
                    m(I::SendInstruction,
                        target: ins[1].result,
                        method_name: :b,
                    ),
                ]),
            )
        ]
    end 
end
