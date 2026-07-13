# frozen_string_literal: true

# Parks the current Resolve timeline's playhead at a timeline frame, for the
# Tier-2 visual pass (skills/integration-tests/SKILL.md). Installs the
# in-app park script and triggers it via the Workspace > Scripts menu — the
# same mechanism as qa/scripts/verify_resolve.rb, so it works on the free
# edition.
#
# Usage (from the repo root; Resolve must be running with the QA project open):
#   ruby skills/integration-tests/resolve_park.rb <timeline_frame> [timeline_name]
#
# Prints the park report JSON (tc_set + Resolve's own tc_readback) on success.

require 'fileutils'
require 'json'
require_relative '../../qa/scripts/qa_helpers'

SCRIPT_SRC  = File.join(__dir__, 'resolve', 'ButterCut QA Park.lua')
SCRIPT_DST  = File.expand_path('~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/ButterCut QA Park.lua')
JOB_PATH    = '/tmp/buttercut_qa_park_job.lua'
REPORT_PATH = '/tmp/buttercut_qa_park_report.json'

frame = Integer(ARGV[0], exception: false)
abort 'Usage: ruby resolve_park.rb <timeline_frame> [timeline_name]' unless frame

unless File.exist?(SCRIPT_DST) && File.read(SCRIPT_DST) == File.read(SCRIPT_SRC)
  FileUtils.mkdir_p(File.dirname(SCRIPT_DST))
  FileUtils.cp(SCRIPT_SRC, SCRIPT_DST)
  puts "Installed in-app script -> #{SCRIPT_DST}"
end

File.write(JOB_PATH, <<~LUA)
  return {
    frame = #{frame},
    report_path = #{REPORT_PATH.inspect},
    #{ARGV[1] ? "timeline_name = #{ARGV[1].inspect}," : ''}
  }
LUA
FileUtils.rm_f([REPORT_PATH, "#{REPORT_PATH}.tmp"])

QaHarness.ensure_app_ready(process: 'Resolve', app_name: 'DaVinci Resolve', ready_probe: <<~APPLESCRIPT)
  tell application "System Events" to tell process "Resolve"
    return exists menu item "Scripts" of menu "Workspace" of menu bar 1
  end tell
APPLESCRIPT

def click_park_menu_item
  _out, clicked = QaHarness.run_osascript(<<~APPLESCRIPT)
    tell application "System Events"
      tell process "Resolve"
        set frontmost to true
        delay 0.5
        click menu item "ButterCut QA Park" of menu of menu item "Scripts" of menu "Workspace" of menu bar 1
      end tell
    end tell
  APPLESCRIPT
  clicked
end

unless click_park_menu_item
  # The Scripts menu only re-scans when opened, so a freshly installed script
  # isn't listed yet — open Workspace once, dismiss it, and retry.
  QaHarness.run_osascript(<<~APPLESCRIPT)
    tell application "System Events"
      tell process "Resolve"
        set frontmost to true
        delay 0.5
        click menu bar item "Workspace" of menu bar 1
        delay 1
        key code 53
      end tell
    end tell
  APPLESCRIPT
  sleep 1
  abort 'menu click failed — is Accessibility permission granted?' unless click_park_menu_item
end

unless QaHarness.wait_until(tries: 20, interval: 1) { File.exist?(REPORT_PATH) }
  abort "No report at #{REPORT_PATH} after 20s — check Resolve's console (Workspace > Console)"
end

report = JSON.parse(File.read(REPORT_PATH))
abort "Park failed: #{report['error']}" unless report['ok']

puts JSON.pretty_generate(report)
