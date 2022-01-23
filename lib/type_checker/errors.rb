module TypeChecker
    module Errors
        class Error
            def initialize(message, tagged_ranges)
                @message = message
                @tagged_ranges = tagged_ranges
            end

            # @return [String]
            attr_reader :message

            # @return [(Parser::Source::Range, String)]
            attr_reader :tagged_ranges

            def format
                # TODO: merge nearby errors

                (["Error: #{message}"] \
                + tagged_ranges.flat_map do |range, hint|
                    # TODO: won't work if the error spans multiple lines
                    line_range = range.source_buffer.line_range(range.line)
                    begin_pos_on_line = range.begin_pos - line_range.begin_pos
                    length = range.end_pos - range.begin_pos

                    [
                        "",
                        "  #{range.source_buffer.name}",
                        "  #{range.line}  |  #{range.source_line}",
                        "  #{' ' * range.line.to_s.length}     #{' ' * begin_pos_on_line}#{'^' * length} #{hint}",
                    ]
                end).join("\n")
            end

            def push
                Errors.push(self)
            end
        end

        @errors = []

        def self.reset
            @errors = []
        end

        def self.push(error)
            @errors << error
        end

        def self.errors
            @errors
        end
    end
end
