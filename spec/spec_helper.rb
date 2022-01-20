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
end

def m(type, **attrs)
  if attrs.length > 0
      be_a(type) & have_attributes(**attrs)
  else
      be_a(type)
  end
end
