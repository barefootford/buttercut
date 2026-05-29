require_relative '../lib/buttercut'

# Support helpers (fixture resolution, shared contexts, etc.).
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |file| require file }

# The contact-sheet skill prints a per-run summary on stdout; specs that exercise it use
# this to keep the rspec output clean unless something actually fails.
module SilenceStdout
  def silence_stdout
    original = $stdout
    $stdout = File.open(File::NULL, 'w')
    yield
  ensure
    $stdout.close
    $stdout = original
  end
end

RSpec.configure do |config|
  config.include SilenceStdout

  # Benchmark specs are opt-in: `rspec --tag benchmark`. They generate larger synthetic
  # clips and exercise wall-time-sensitive paths, so we don't run them by default.
  config.filter_run_excluding benchmark: true

  # Fixture-dependent specs are opt-in: `rspec --tag fixtures`. They require sample
  # video files under spec/assets/ (gitignored), so they're skipped on fresh clones / CI.
  config.filter_run_excluding fixtures: true

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.after(:suite) do
    if RSpec.configuration.exclusion_filter[:benchmark]
      puts "\nTip: benchmark specs were skipped. On a dev machine, run them with:"
      puts "  bundle exec rspec --tag benchmark"
    end
  end
end
