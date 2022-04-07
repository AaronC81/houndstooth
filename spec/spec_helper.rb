require 'simplecov'
SimpleCov.start if defined?(RSpec)

require_relative '../lib/houndstooth'

RSpec.configure do |config|
    config.expect_with :rspec do |expectations|
        expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    end

    config.mock_with :rspec do |mocks|
        mocks.verify_partial_doubles = true
    end

    config.shared_context_metadata_behavior = :apply_to_host_groups

    config.before :each do
        Houndstooth::Errors.reset
    end

    config.after :each do
        if Houndstooth::Errors.errors.any?
            errors = Houndstooth::Errors.errors.map { |e| e.format }.join("\n")
            raise "Errors occurred during test:\n#{errors}"
        end
    end
end if defined?(RSpec)

def m(type, **attrs)
    if attrs.length > 0
        be_a(type) & have_attributes(**attrs)
    else
        be_a(type)
    end
end

def code_to_semantic_node(code)
    buffer = Parser::Source::Buffer.new("arg")
    buffer.source = code

    ast_node, comments = Parser::Ruby30.new.parse_with_comments(buffer)
    $comments = comments
    Houndstooth::SemanticNode.from_ast(ast_node)
end

def code_to_block(code)
    block = I::InstructionBlock.new(has_scope: true, parent: nil)
    code_to_semantic_node(code).to_instructions(block)
    block
end
