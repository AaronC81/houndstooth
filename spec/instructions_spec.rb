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
end
