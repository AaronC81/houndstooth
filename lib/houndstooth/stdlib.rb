module Houndstooth::Stdlib
    def self.add_types(environment)
        Houndstooth.process_file('stdlib.htt', File.read(File.join(__dir__, '..', '..', 'types', 'stdlib.htt')), environment)
        environment.resolve_all_pending_types
    end
end
