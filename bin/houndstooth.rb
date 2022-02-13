require 'optimist'
require_relative '../lib/houndstooth'

options = Optimist::options do
    banner "Houndstooth: A Ruby type checker"

    opt :file, "file to type check", type: :string, short: :f
    opt :code, "code string to type check", type: :string, short: :e

    opt :no_stdlib, "don't load stdlib types", short: :s

    opt :debug_nodes, "print parsed node tree", short: :none
    opt :debug_environment, "print known types and methods", short: :none
    opt :debug_instructions, "print generated instructions", short: :none
    opt :debug_type_changes, "print instructions after type changes", short: :none
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

# Load and parse code from file
if options[:file]
    Optimist::die("file '#{options[:file]}' does not exist") unless File.exist?(options[:file])
    code = File.read(options[:file])
elsif options[:code]
    code = options[:code]
else
    Optimist::die("must pass either --file/-f or --code/-e")
end

if options[:no_stdlib]
    htt_files = []
else
    htt_files = [["stdlib.htt", File.read(File.join(__dir__, '..', 'types', 'stdlib.htt'))]]
end

# Parse and run builder over all files
all_nodes = [[options[:file] || 'inline code', code], *htt_files].map do |name, contents|
    Houndstooth.process_file(name, contents, env) 
end
node = all_nodes[0]
abort_on_error!

if options[:debug_nodes]
    puts "------ Nodes ------"
    pp node
    puts "-------------------"
end

# Resolve environment
env.resolve_all_pending_types
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
block.lexical_context_change = Houndstooth::Environment::BaseDefinedType.new
env.types["__HoundstoothMain"] = Houndstooth::Environment::DefinedType.new(path: "__HoundstoothMain")
block.self_type_change = env.types["__HoundstoothMain"]
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

if options[:debug_type_changes]
    puts "--- Inst. Types ---"
    puts block.to_assembly
    puts "-------------------"
end

# Yay!
puts "All good!"
