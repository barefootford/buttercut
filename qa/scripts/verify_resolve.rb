# frozen_string_literal: true

# DaVinci Resolve leg of the editor round-trip QA harness: imports a
# ButterCut-exported timeline into a scratch Resolve project and verifies,
# frame-accurately, that Resolve built the timeline the cut described.
#
# Works on the free edition (where external scripting is unavailable) by
# driving Resolve's own Workspace > Scripts menu: the in-app Lua script
# (qa/scripts/resolve/ButterCut QA Dump.lua) does the import and dumps what
# Resolve actually built; this runner installs that script, triggers the menu
# item via System Events, normalizes the dump, and compares it against the
# fixture's expected_<scenario>.json.
#
# Usage (from the repo root; Resolve may be closed — it will be launched):
#   ruby qa/scripts/verify_resolve.rb [xml_path] [expected_json_path]
#
# Defaults to the qa-editor-roundtrip fixture's resolve export. Exits 0 on
# pass, 1 on fail. Requires Accessibility permission for the terminal/agent
# process (System Events drives the menu click).

require 'fileutils'
require 'json'
require_relative 'qa_helpers'

SCRIPT_SRC  = File.join(__dir__, 'resolve', 'ButterCut QA Dump.lua')
SCRIPT_DST  = File.expand_path('~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/ButterCut QA Dump.lua')
JOB_PATH    = '/tmp/buttercut_qa_resolve_job.lua'
REPORT_PATH = '/tmp/buttercut_qa_resolve_report.json'

xml_path, expected_path = QaHarness.verify_args('resolve')

unless File.exist?(SCRIPT_DST) && File.read(SCRIPT_DST) == File.read(SCRIPT_SRC)
  FileUtils.mkdir_p(File.dirname(SCRIPT_DST))
  FileUtils.cp(SCRIPT_SRC, SCRIPT_DST)
  puts "Installed in-app script -> #{SCRIPT_DST}"
end

File.write(JOB_PATH, <<~LUA)
  return {
    xml_path = #{xml_path.inspect},
    report_path = #{REPORT_PATH.inspect},
    timeline_name = #{"buttercut-qa-#{File.basename(xml_path, '.*')}".inspect},
  }
LUA
FileUtils.rm_f([REPORT_PATH, "#{REPORT_PATH}.tmp"])

QaHarness.ensure_app_ready(process: 'Resolve', app_name: 'DaVinci Resolve', ready_probe: <<~APPLESCRIPT)
  tell application "System Events" to tell process "Resolve"
    return exists menu item "Scripts" of menu "Workspace" of menu bar 1
  end tell
APPLESCRIPT

puts 'Triggering Workspace > Scripts > ButterCut QA Dump...'
_out, clicked = QaHarness.run_osascript(<<~APPLESCRIPT)
  tell application "System Events"
    tell process "Resolve"
      set frontmost to true
      delay 0.5
      click menu item "ButterCut QA Dump" of menu of menu item "Scripts" of menu "Workspace" of menu bar 1
    end tell
  end tell
APPLESCRIPT
abort 'menu click failed — is Accessibility permission granted?' unless clicked

unless QaHarness.wait_until(tries: 60, interval: 2) { File.exist?(REPORT_PATH) }
  abort "No report at #{REPORT_PATH} after 2 minutes — check Resolve's console (Workspace > Console)"
end

report = JSON.parse(File.read(REPORT_PATH))
abort "Resolve script failed: #{report['error']}" unless report['ok']

timeline = report.fetch('timeline')
start_frame = timeline['start_frame'].to_i
video_items = report.fetch('video_tracks').flat_map { |t| t['items'] }

actual = {
  'editor' => "#{report['product']} #{report['resolve_version']}",
  'timeline' => {
    'frame_rate' => timeline['frame_rate'],
    'width' => timeline['width'],
    'height' => timeline['height'],
    'total_frames' => timeline['end_frame'].to_i - start_frame
  },
  'clips' => video_items.map do |item|
    still = item['media_type'].to_s == 'Still'
    clip = {
      'source' => File.basename(item['media_path'] || item['name'].to_s),
      'type' => still ? 'image' : 'video',
      'record_in' => item['start'].to_i - start_frame,
      'record_out' => item['end'].to_i - start_frame
    }
    unless still
      # left_offset (frames between media start and the clip's in-point) is
      # file-relative even when the media carries an embedded start timecode;
      # source_start_frame is kept as the fallback for older Resolve APIs.
      source_in = item['left_offset'] || item['source_start_frame']
      clip['source_in']  = source_in
      clip['source_out'] = source_in + (item['source_end_frame'].to_i - item['source_start_frame'].to_i)
    end
    clip
    # mute is not observable through Resolve's API — compare_timeline reports it as skipped
  end
}

QaHarness.finish!(actual, xml_path: xml_path, expected_path: expected_path,
                  label: "DaVinci Resolve import of #{File.basename(xml_path)}")
