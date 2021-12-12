RSpec.describe 'self-test' do
    it 'does not fail when trying to parse this project' do
        Dir[File.join(__dir__, '..', '**', '*.rb')].each do |file|
            code_to_semantic_node(File.read(file))
        end
    end
end
