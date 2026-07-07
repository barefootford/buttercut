# frozen_string_literal: true

# Shared plumbing for the editor round-trip QA harness: the fixture's
# canonical paths, the scenario and editor registries, and the small helpers
# every verifier leg would otherwise copy-paste (arg parsing, condition
# polling, osascript, and the write-dump/compare/report/exit tail).
# Editor-specific driving stays in the verify_* scripts.

require 'json'
require 'open3'
require_relative 'compare_timeline'
require_relative '../../lib/buttercut/library'

module QaHarness
  REPO_ROOT    = File.expand_path('../..', __dir__)
  LIBRARY_NAME = 'qa-editor-roundtrip'
  FIXTURE_DIR  = File.join(Library::LIBRARIES_ROOT, LIBRARY_NAME)
  CUTS_DIR     = File.join(FIXTURE_DIR, 'cuts')

  # Every scenario cut, tagged by tier. :fast runs on every `run_all.rb`;
  # :full scenarios join in with --full. The generator owns each scenario's
  # actual definition (clips, media, expected math) under the same names.
  SCENARIOS = {
    'canonical-30' => :fast,
    'ntsc-2997-df' => :full,
    'film-23976'   => :full
  }.freeze
  DEFAULT_SCENARIO = 'canonical-30'

  # One row per editor leg, in the order the legs run. Premiere is never
  # pre-warmed: its leg must launch its own instance.
  EDITORS = {
    'resolve'  => { name: 'DaVinci Resolve', ext: '.xml',
                    app: '/Applications/DaVinci Resolve/DaVinci Resolve.app',
                    verifier: 'qa/scripts/verify_resolve.rb', prewarm: true },
    'fcpx'     => { name: 'Final Cut Pro', ext: '.fcpxml',
                    app: '/Applications/Final Cut Pro.app',
                    verifier: 'qa/scripts/verify_fcp.rb', prewarm: true },
    'premiere' => { name: 'Premiere', ext: '.xml',
                    app: Dir.glob('/Applications/Adobe Premiere*/Adobe Premiere*.app').first,
                    verifier: 'qa/scripts/verify_premiere.rb', prewarm: false }
  }.freeze

  module_function

  def scenario_names(full: false)
    full ? SCENARIOS.keys : SCENARIOS.filter_map { |name, tier| name if tier == :fast }
  end

  # 30 for whole rates, 29.97/23.976-style rounded decimals for NTSC — the one
  # frame-rate normalization the generator and every verifier leg must share,
  # because the comparison is exact.
  def fps_value(fps) = fps.denominator == 1 ? fps.to_i : fps.to_f.round(3)

  def cut_yaml(scenario) = File.join(CUTS_DIR, "#{scenario}.yaml")

  def expected_json(scenario) = File.join(FIXTURE_DIR, "expected_#{scenario}.json")

  def export_path(editor_key, scenario)
    File.join(CUTS_DIR, "#{scenario}_#{editor_key}#{EDITORS.fetch(editor_key)[:ext]}")
  end

  def premiere_binary
    app = EDITORS.dig('premiere', :app)
    app && Dir.glob(File.join(app, 'Contents/MacOS/Adobe Premiere*')).first
  end

  def verify_args(editor_key)
    xml_path      = File.expand_path(ARGV[0] || export_path(editor_key, DEFAULT_SCENARIO))
    expected_path = File.expand_path(ARGV[1] || expected_json(DEFAULT_SCENARIO))
    abort "No exported XML at #{xml_path} — run generate_qa_fixture.rb and export first" unless File.exist?(xml_path)
    abort "No expected timeline at #{expected_path} — run generate_qa_fixture.rb first" unless File.exist?(expected_path)

    [xml_path, expected_path]
  end

  def wait_until(tries:, interval: 1)
    tries.times do
      return true if yield

      sleep interval
    end
    false
  end

  def run_osascript(body)
    out, _err, status = Open3.capture3('osascript', '-', stdin_data: body)
    [out.strip, status.success?]
  end

  def osascript(body)
    out, ok = run_osascript(body)
    abort "osascript failed: #{out}" unless ok

    out
  end

  def osascript_true?(body) = run_osascript(body) == ['true', true]

  # Launch `app_name` if `process` isn't running, then poll the AppleScript
  # `ready_probe` (must return a boolean) until the app is driveable.
  def ensure_app_ready(process:, app_name:, ready_probe:)
    unless system('pgrep', '-xq', process)
      puts "Launching #{app_name}..."
      system('open', '-a', app_name) || abort("could not launch #{app_name}")
    end
    ready = wait_until(tries: 90, interval: 2) { osascript_true?(ready_probe) }
    abort "#{app_name} never became ready after 3 minutes" unless ready
  end

  # The shared leg tail: dump goes next to the export (whose name already
  # carries the scenario and editor), compare, report, exit 0/1.
  def finish!(actual, xml_path:, expected_path:, label:)
    actual_path = File.join(File.dirname(xml_path), "qa-actual_#{File.basename(xml_path, '.*')}.json")
    File.write(actual_path, JSON.pretty_generate(actual) + "\n")

    result = QaCompare.compare(JSON.parse(File.read(expected_path)), actual)
    puts QaCompare.report(result, label: label)
    puts "  actual: #{actual_path}"
    exit(result['pass'] ? 0 : 1)
  end
end
