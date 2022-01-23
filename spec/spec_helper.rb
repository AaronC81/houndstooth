require_relative '../lib/type_checker'
require_relative '../lib/cli'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.before :each do
    TypeChecker::Errors.reset
  end

  config.after :each do
    if TypeChecker::Errors.errors.any?
      errors = TypeChecker::Errors.errors.map { |e| e.format }.join("\n")
      raise "Errors occurred during test:\n#{errors}"
    end
  end
end

def m(type, **attrs)
  if attrs.length > 0
      be_a(type) & have_attributes(**attrs)
  else
      be_a(type)
  end
end
