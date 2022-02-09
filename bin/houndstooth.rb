require 'optimist'
require_relative '../lib/houndstooth'

options = Optimist::options do
    banner "Houndstooth: A Ruby type checker"

    opt :file, "file to type check", short: :f
    opt :code, "code string to type check", type: :string, short: :e

    opt :no_stdlib, "don't load stdlib types", short: :s

    opt :debug_nodes, "print parsed node tree", short: :none
    opt :debug_environment, "print known types and methods", short: :none
    opt :debug_instructions, "print generated instructions", short: :none
end

# Checks if there are any errors. If so, prints them and aborts.
def abort_on_error!
    if Houndstooth::Errors.errors.any?
        Houndstooth::Errors.errors.each do |error|
            puts error.format
            puts
        end

        l = Houndstooth::Errors.errors.length
        abort "Exiting with #{l} error#{l == 1 ? '' : 's'}."
    end
end 

# Create an environment with stdlib types
env = Houndstooth::Environment.new
Houndstooth::Stdlib.add_types(env) unless options[:no_stdlib]

# Load and parse code from file
if options[:file]
    Optimist::die("file '#{options[:file]}' does not exist") unless File.exist?(options[:file])
    code = File.read(options[:file])
elsif options[:code]
    code = options[:code]
else
    Optimist::die("must pass either --file/-f or --code/-e")
end

buffer = Parser::Source::Buffer.new(options[:file] || 'inline code')
buffer.source = code

ast_node, comments = Parser::Ruby30.new.parse_with_comments(buffer)
$comments = comments
node = Houndstooth::SemanticNode.from_ast(ast_node)
abort_on_error!

if options[:debug_nodes]
    puts "------ Nodes ------"
    pp node
    puts "-------------------"
end

# Run builder over parsed code
Houndstooth::Environment::Builder.new(node, env).analyze
abort_on_error!

if options[:debug_environment]
    puts "--- Environment ---"
    env.types.each do |_, t|
        puts t.path
        t.instance_methods.each do |m|
            puts "  #{m.name}"
            m.signatures.each do |s|
                puts "    #{s.rbs}"
            end
        end
        puts
    end
    puts "-------------------"
end

# Create a new instruction block and populate it
# TODO: this is probably not how it'll be done in the final thing - we need to do this to individual
# methods, probably, or just ignore definitions? Don't know!
block = Houndstooth::Instructions::InstructionBlock.new(has_scope: true, parent: nil)
node.to_instructions(block)
abort_on_error!

if options[:debug_instructions]
    puts "-- Instructions ---"
    puts block.to_assembly
    puts "-------------------"
end

# Type check the instruction block
checker = Houndstooth::TypeChecker.new(env)
checker.process_block(block)
abort_on_error!

# Yay!
puts "All good!"
