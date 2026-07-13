# frozen_string_literal: true

# Launches Premiere with every scenario's FCP7 XML imported into one scratch
# project, all sequences open as timeline tabs, project saved — and leaves
# Premiere RUNNING for the Tier-2 visual pass
# (skills/integration-tests/SKILL.md).
#
# Premiere only executes scripts at launch, so like the Tier-1 leg this must
# start its own instance and refuses to run when Premiere is already open.
# Because the script saves the project, quitting Premiere afterwards is
# dialog-free:
#   osascript -e 'tell application id "com.adobe.PremierePro" to quit'
#
# Usage (from the repo root; exports must exist — run Tier 1 first):
#   ruby skills/integration-tests/premiere_open_all.rb [xml ...]
#
# Defaults to every scenario export present under the fixture's cuts/.

require 'fileutils'
require 'json'
require_relative '../../qa/scripts/qa_helpers'

TEMPLATE     = File.join(__dir__, 'premiere', 'buttercut_qa_open_all.jsx.template')
JSX_PATH     = '/tmp/buttercut_qa_premiere_open_all.jsx'
REPORT_PATH  = '/tmp/buttercut_qa_premiere_open_all_report.json'
PROJECT_PATH = '/tmp/buttercut_qa_premiere_tier2.prproj'

xml_paths = if ARGV.any?
              ARGV.map { |p| File.expand_path(p) }
            else
              QaHarness::SCENARIOS.keys.map { |s| QaHarness.export_path('premiere', s) }.select { |p| File.exist?(p) }
            end
abort 'No scenario exports found — run `ruby qa/scripts/run_all.rb --full` (or export manually) first' if xml_paths.empty?
missing = xml_paths.reject { |p| File.exist?(p) }
abort "Missing XML: #{missing.join(', ')}" if missing.any?

premiere_bin = QaHarness.premiere_binary
abort 'No Adobe Premiere binary found under /Applications' unless premiere_bin

if system('pgrep -fq "Adobe Premiere"')
  abort 'Adobe Premiere is already running — quit it first (Premiere only executes scripts at launch).'
end

jsx = File.read(TEMPLATE)
      .gsub('__XML_PATHS__', JSON.generate(xml_paths))
      .gsub('__REPORT_PATH__', REPORT_PATH)
      .gsub('__PROJECT_PATH__', PROJECT_PATH)
File.write(JSX_PATH, jsx)
FileUtils.rm_f([REPORT_PATH, "#{REPORT_PATH}.tmp", PROJECT_PATH])

puts "Launching #{File.basename(premiere_bin)} with #{xml_paths.length} scenario XML(s) (takes a minute)..."
pid = Process.spawn(premiere_bin, '/C', "es.processFile #{JSX_PATH}", %i[out err] => '/dev/null')
Process.detach(pid)

unless QaHarness.wait_until(tries: 150, interval: 2) { File.exist?(REPORT_PATH) }
  abort "No report at #{REPORT_PATH} after 5 minutes — see the Premiere notes in qa/editor-roundtrip.md. " \
        'Premiere was left running; quit it by hand.'
end

report = JSON.parse(File.read(REPORT_PATH))
abort "Premiere script failed at stage '#{report['stage']}': #{report['error']} (Premiere left running)" unless report['ok']

puts "✓ Premiere is open with sequences: #{report['sequences'].join(', ')}"
puts '  Park the playhead by clicking the Program monitor timecode field, typing digits, Enter.'
puts '  Quit when done (project already saved): osascript -e \'tell application id "com.adobe.PremierePro" to quit\''
