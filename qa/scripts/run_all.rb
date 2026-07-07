# frozen_string_literal: true

# Runs the editor round-trip suite: fixture → exports → one verifier per
# installed editor per scenario. This is the deterministic tier of
# qa/editor-roundtrip.md — read that runbook for prerequisites, the visual
# tier, and troubleshooting.
#
# Usage (from the repo root):
#   ruby qa/scripts/run_all.rb [--full] [--skip-generate]
#
# Default runs the :fast scenarios (the canonical cut, <30s per editor);
# --full adds every matrix scenario (frame rates, embedded timecode, …).
# Runs every applicable leg even when an earlier one fails; exits non-zero if
# any leg failed. Legs whose editor isn't installed are reported as SKIP.

require_relative 'qa_helpers'
require_relative '../../lib/buttercut/version'

def run(desc, *cmd)
  puts "\n=== #{desc}\n"
  system(*cmd)
end

Dir.chdir(QaHarness::REPO_ROOT)

scenarios = QaHarness.scenario_names(full: ARGV.include?('--full'))
edition = "#{ButterCut::EDITION} #{ButterCut::VERSION}"
installed = QaHarness::EDITORS.select { |_, leg| leg[:app] && File.exist?(leg[:app]) }
puts "ButterCut edition under test: #{edition}"
puts "Scenarios: #{scenarios.join(', ')}"

# Pre-warm the GUI editors (background launch, no focus steal) so their cold
# start overlaps the CPU-only fixture/export work instead of extending each leg.
installed.each_value do |leg|
  next unless leg[:prewarm]

  system('open', '-g', '-a', leg[:name], out: File::NULL, err: File::NULL)
end

unless ARGV.include?('--skip-generate')
  run('Generating fixture', 'ruby', 'qa/scripts/generate_qa_fixture.rb') || abort('fixture generation failed')
end

scenarios.each do |scenario|
  cut = QaHarness.cut_yaml(scenario)
  abort "No cut at #{cut}" unless File.exist?(cut)

  installed.each_key do |editor|
    run("Exporting #{scenario} for #{editor}",
        'ruby', 'lib/buttercut/export.rb', '--editor', editor, cut, QaHarness.export_path(editor, scenario)) ||
      abort("export failed for #{scenario}/#{editor}")
  end
end

# Verify editor-by-editor so each app's scenarios run back to back (one warm
# stretch per editor; Premiere still launches once per scenario — see the
# runbook's batching note).
results = QaHarness::EDITORS.flat_map do |editor, leg|
  unless installed.key?(editor)
    puts "\n=== #{leg[:name]}: SKIP (not installed)"
    next scenarios.map { |scenario| ["#{leg[:name]} · #{scenario}", 'SKIP'] }
  end

  scenarios.map do |scenario|
    ok = run("Verifying #{leg[:name]} · #{scenario}",
             'ruby', leg[:verifier], QaHarness.export_path(editor, scenario), QaHarness.expected_json(scenario))
    ["#{leg[:name]} · #{scenario}", ok ? 'PASS' : 'FAIL']
  end
end

puts "\n#{'=' * 46}\nEditor round-trip results (#{edition}):"
results.each { |name, status| puts format('  %-34s %s', name, status) }
puts '=' * 46
exit(results.none? { |_, s| s == 'FAIL' } ? 0 : 1)
