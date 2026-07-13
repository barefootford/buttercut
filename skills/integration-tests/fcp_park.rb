# frozen_string_literal: true

# Parks the Final Cut Pro playhead at a timeline frame, for the Tier-2 visual
# pass (skills/integration-tests/SKILL.md). FCP has no scripting API,
# so this types the position: Cmd+2 (focus the timeline), Ctrl+P (Go To
# Playhead Position), the timecode digits, Return.
#
# The digits are computed NDF at the nominal integer rate (30 for 29.97, 24
# for 23.976) — exact for the QA timelines, which start at 0 and run well
# under a minute.
#
# Usage (FCP must be running with the QA project open in the timeline):
#   ruby skills/integration-tests/fcp_park.rb <timeline_frame> <fps>
#   ruby skills/integration-tests/fcp_park.rb 315 30      # -> types 1015 (0:10:15)

require_relative '../../qa/scripts/qa_helpers'

frame = Integer(ARGV[0], exception: false)
fps   = Float(ARGV[1] || '', exception: false)
abort 'Usage: ruby fcp_park.rb <timeline_frame> <fps>' unless frame && fps

nominal = fps.round
ff = frame % nominal
total_s = frame / nominal
digits = format('%d%02d%02d', total_s / 60, total_s % 60, ff).sub(/\A0+(?=\d)/, '')

QaHarness.osascript(<<~APPLESCRIPT)
  tell application "System Events"
    tell process "Final Cut Pro"
      set frontmost to true
      delay 0.5
      keystroke "2" using {command down}
      delay 0.3
      keystroke "p" using {control down}
      delay 0.3
      keystroke "#{digits}"
      delay 0.2
      key code 36
    end tell
  end tell
APPLESCRIPT

puts "Parked FCP at frame #{frame} (typed #{digits} @ #{nominal} fps NDF)"
