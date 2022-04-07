require_relative '../lib/houndstooth'
require_relative '../spec/spec_helper' # contains code_to_X methods

def run(command)
    out = `#{command}`
    abort "command failed: #{command}" unless $?.success?
    out
end

# Perform a sparse checkout of the Ruby repository to grab bootstraptest
ruby_dir = File.join(__dir__, "ruby")
if Dir.exist?(ruby_dir)
    puts "Ruby directory already exists, skipping checkout"
else
    puts "Sparse-checking out Ruby..."
    Dir.mkdir(ruby_dir)
    Dir.chdir(ruby_dir) do
        run("git init")
        run("git remote add -f origin https://github.com/ruby/ruby.git")
        run("git config core.sparseCheckout true")
        File.write(File.join(ruby_dir, ".git", "info", "sparse-checkout"), "bootstraptest/")
        run("git pull origin master")
    end
end

I = Houndstooth::Instructions

# Required for Houndstooth.process_file, which expects to be run from the binary
def abort_on_error!
    if Houndstooth::Errors.errors.any?
        raise "Errors occurred during interpretation:\n#{Houndstooth::Errors.errors.map(&:format).join("\n")}"
    end
end 

def interpreter_execute(code)
    # Create environment
    env = Houndstooth::Environment.new
    Houndstooth::Stdlib.add_types(env)

    # Process input
    Houndstooth.process_file('(test)', code, env)

    # Process and evaluate input
    block = code_to_block(code)
    runtime = Houndstooth::Interpreter::Runtime.new(env: env)
    runtime.execute_block(
        block,
        self_type: nil,
        self_object: nil,
        lexical_context: Houndstooth::Environment::BaseDefinedType.new,
        type_arguments: {},
    )

    # If an error occurred, throw
    abort_on_error!

    # Get return value
    runtime.variables[block.instructions.last.result]
end

$bootstrap_test_passes = []
$bootstrap_test_failures = []
$bootstrap_test_crashes = []
$bootstrap_test_unimplemented = []

module BootstrapTestHarness
    def self.clear_errors
        Houndstooth::Errors.errors.clear
    end 

    def self.target_platform
        ""
    end

    def self.assert_equal(expected_result, code, *_)
        clear_errors

        actual_result = interpreter_execute(code)
        if actual_result.ruby_inspect == expected_result
            $bootstrap_test_passes << [expected_result, code]
        else
            $bootstrap_test_failures << [expected_result, code]
        end
    rescue => e
        $bootstrap_test_crashes << [expected_result, code]
    end

    def self.assert_match(matcher, code, *_)
        clear_errors

        actual_result = interpreter_execute(code)
        if matcher === actual_result.ruby_inspect
            $bootstrap_test_passes << [matcher, code]
        else
            $bootstrap_test_failures << [matcher, code]
        end
    rescue
        $bootstrap_test_crashes << [matcher, code]
    end

    def self.assert_normal_exit(code, message="(normal exit)", *_)
        clear_errors
        interpreter_execute(code)
    rescue
        $bootstrap_test_crashes << [message, code]
    end

    def self.assert_valid_syntax(code, *_)
        clear_errors
        assert_normal_exit(code, "(valid syntax)")
    end

    def self.method_missing(*a)
        $bootstrap_test_unimplemented << a
    end
end

Dir[File.join(ruby_dir, "bootstraptest", "test_*.rb")].each do |file|
    puts file
    test = File.read(file)
    BootstrapTestHarness.instance_eval(test, file)
end

puts "Passes: #{$bootstrap_test_passes.length}"
puts "Failures: #{$bootstrap_test_failures.length}"
puts "Crashes: #{$bootstrap_test_crashes.length}"
puts "Unimplemented tests: #{$bootstrap_test_unimplemented.length}"
