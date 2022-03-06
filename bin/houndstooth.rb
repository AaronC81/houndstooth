require 'optimist'
require 'afl'
require_relative '../lib/houndstooth'

options = Optimist::options do
    banner "Houndstooth: A Ruby type checker"

    opt :file, "file to type check", type: :string, short: :f
    opt :code, "code string to type check", type: :string, short: :e

    opt :no_stdlib, "don't load stdlib types (for debugging - almost guaranteed to cause weird problems!)", short: :s
    opt :fatal_interpreter, "exit on first interpreter error, and print internal backtrace", short: :x

    opt :debug_nodes, "print parsed node tree", short: :none
    opt :debug_environment, "print known types and methods", short: :none
    opt :debug_instructions, "print generated instructions", short: :none
    opt :debug_type_changes, "print instructions after type changes", short: :none
    opt :verbose_instructions, "show more detail in instruction debug views", short: :none

    opt :instrument, "AFL instrumentation", short: :none
end

def main(options)
    $cli_options = options
    # Checks if there are any errors. If so, prints them and aborts.
    def abort_on_error!
        if Houndstooth::Errors.errors.any?
            Houndstooth::Errors.errors.each do |error|
                puts error.format
                puts
            end

            # The fuzzer will view an abort as a crash, so if we're running under instrumentation,
            # exit gracefully here
            l = Houndstooth::Errors.errors.length
            if $cli_options[:instrument]
                puts "Exiting with #{l} error#{l == 1 ? '' : 's'}."
                puts "Running with instrumentation, so exit is just a jump."
                puts "THIS WILL NOT RESULT IN AN ERROR EXIT CODE."
                throw :afl_exit
            else
                abort "Exiting with #{l} error#{l == 1 ? '' : 's'}."
            end
        end
    end 

    # Create an environment with stdlib types
    env = Houndstooth::Environment.new

    # Load and parse code from file
    if options[:file]
        unless File.exist?(options[:file])
            Houndstooth::Errors::Error.new("File '#{options[:file]}' does not exist", []).push
            abort_on_error!
        end

        begin
            code = File.read(options[:file])
        rescue => e
            Houndstooth::Errors::Error.new("Error reading file: #{e}", []).push
            abort_on_error!
        end
    elsif options[:code]
        code = options[:code]
    else
        puts "
███████▖  ▀██ 
████████▙▖  ▜ 
██████▌▜██▄           HOUNDSTOOTH
██████▌ ▝▜██▖     A Ruby type checker
▝██▙▖         
  ▀██▙           -f/--file: Check file
▙  ▝▜█▌         -e/--code: Check string
██▄  ▝▌       
"
        exit 1
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
            if t.type_instance_variables.any?
                puts "  Vars:"
                t.type_instance_variables.each do |k, v|
                    puts "    #{k}: #{v.rbs}"
                end
            end
            t.instance_methods.each do |m|
                puts "  #{m.name}"
                # Don't try to print special `new`
                if m.is_a?(Houndstooth::Environment::SpecialConstructorMethod)
                    puts "    <special constructor>"
                else
                    m.signatures.each do |s|
                        puts "    #{s.rbs}"
                    end
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
    env.types["__HoundstoothMain"] = Houndstooth::Environment::DefinedType.new(path: "__HoundstoothMain")
    abort_on_error!

    if options[:debug_instructions]
        puts "-- Instructions ---"
        puts block.to_assembly
        puts "-------------------"
    end

    # Run the interpreter
    runtime = Houndstooth::Interpreter::Runtime.new(env: env)
    runtime.execute_from_top_level(block)
    abort_on_error!

    # Type check the instruction block
    checker = Houndstooth::TypeChecker.new(env)
    checker.process_block(
        block,
        lexical_context: Houndstooth::Environment::BaseDefinedType.new,
        self_type: env.types["__HoundstoothMain"]
    )
    
    if options[:debug_type_changes]
        puts "--- Inst. Types ---"
        puts block.to_assembly
        puts "-------------------"
    end
    abort_on_error!

    # Yay!
    puts "All good!"
end

if options[:instrument]
    puts "== Instrumentation enabled =="
    AFL.init
    AFL.with_logging_to_file("/tmp/houndstooth-afl") do
        catch :afl_exit do
            AFL.with_exceptions_as_crashes do
                main(options)
            end
        end
    end
else
    main(options)
end
