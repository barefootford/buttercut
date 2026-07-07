# frozen_string_literal: true

# Final Cut Pro leg of the editor round-trip QA harness: imports a
# ButterCut-exported FCPXML into a dedicated throwaway FCP library, has FCP
# re-export the imported event as XML, and verifies FCP's own re-serialization
# frame-accurately against the fixture's expected_<scenario>.json.
#
# FCP has no scripting API for this, so the runner drives the UI blind via
# System Events (Accessibility): menu clicks, save-panel keystrokes, and
# sidebar-row reads. Every stage is confirmed on the filesystem (bundle event
# folder appears, re-export lands) rather than by trusting the UI.
#
# The import destination is made deterministic by never choosing from FCP's
# library list: the "Open Library" dialog's New… button creates a fresh
# buttercut-qa-import library as part of the import itself.
#
# Usage (from the repo root; FCP may be closed — it will be launched):
#   ruby qa/scripts/verify_fcp.rb [fcpxml_path] [expected_json_path]
#
# Leaves the buttercut-qa-import.fcpbundle on disk (closed in FCP) for manual
# inspection; the next run deletes and recreates it. Requires Accessibility
# permission for the terminal/agent process. Never touches other libraries.

require 'fileutils'
require 'json'
require 'rexml/document' # stdlib rather than Nokogiri, so the leg runs with plain `ruby` (no bundle exec)
require 'uri'
require_relative 'qa_helpers'

FCP_WORK_DIR = File.join(QaHarness::FIXTURE_DIR, 'fcp')
QA_LIBRARY   = 'buttercut-qa-import'

xml_path, expected_path = QaHarness.verify_args('fcpx')
REEXPORT = "#{File.basename(xml_path, '.*')}-reexport"

# ---------- fcpxml helpers ----------

def rational_seconds(str)
  return Rational(0) if str.nil? || str.empty?

  Rational(str.delete_suffix('s')) # Kernel#Rational parses "3600" and "1001/30000" alike
end

def to_frames(rational, fps)
  value = rational * fps
  raise "#{rational} s is not frame-aligned at #{fps} fps" unless value.denominator == 1

  value.to_i
end

def first_event_name(fcpxml_path)
  doc = REXML::Document.new(File.read(fcpxml_path))
  REXML::XPath.first(doc, '//event/@name')&.value or
    abort("no <event> in #{fcpxml_path} — can't determine import event name")
end

def decoded_basename(file_url)
  File.basename(URI.decode_uri_component(file_url.delete_prefix('file://')))
end

# Parses an FCP "Export XML" re-export (bare .fcpxml or .fcpxmld bundle) into
# the normalized shape compare_timeline.rb expects.
def parse_fcp_reexport(path)
  path = File.join(path, 'Info.fcpxml') if File.directory?(path)
  doc = REXML::Document.new(File.read(path))

  formats = REXML::XPath.match(doc, '//resources/format').each_with_object({}) do |f, hash|
    hash[f.attributes['id']] = {
      frame_duration: rational_seconds(f.attributes['frameDuration']),
      width: f.attributes['width']&.to_i,
      height: f.attributes['height']&.to_i
    }
  end
  # Each asset's own `start` is FCP's reading of the media's embedded start
  # timecode; subtracting it from a clip's start yields the file-relative
  # source in-point — and catches a ButterCut base-timecode bug, because the
  # clip start came from our export while the asset start is FCP's own.
  assets = REXML::XPath.match(doc, '//resources/asset').each_with_object({}) do |a, hash|
    hash[a.attributes['id']] = {
      source: decoded_basename(REXML::XPath.first(a, 'media-rep/@src')&.value.to_s),
      start: rational_seconds(a.attributes['start'])
    }
  end

  sequence = REXML::XPath.first(doc, '//project/sequence') or raise 'no <project><sequence> in re-export'
  seq_format = formats.fetch(sequence.attributes['format'])
  fps = (1 / seq_format[:frame_duration])
  clips = []
  REXML::XPath.first(sequence, 'spine').elements.each do |el|
    offset   = rational_seconds(el.attributes['offset'])
    duration = rational_seconds(el.attributes['duration'])
    asset    = assets[el.attributes['ref']]
    source   = asset&.fetch(:source) || el.attributes['name']
    case el.name
    when 'asset-clip'
      start  = rational_seconds(el.attributes['start'] || '0s') - (asset&.fetch(:start) || Rational(0))
      # Muted clips re-export as adjust-volume -96dB (the exporter's
      # Fcpx::MUTE_VOLUME_ADJUSTMENT); anything ≤ -90 counts as muted — headroom
      # for FCP's re-serialization without copying the lib constant here.
      volume = REXML::XPath.first(el, 'adjust-volume/@amount')&.value.to_s
      clips << { 'source' => source, 'type' => 'video',
                 'record_in' => to_frames(offset, fps), 'record_out' => to_frames(offset + duration, fps),
                 'source_in' => to_frames(start, fps), 'source_out' => to_frames(start + duration, fps),
                 'mute' => volume.to_f <= -90 }
    when 'video' # a held still
      clips << { 'source' => source, 'type' => 'image',
                 'record_in' => to_frames(offset, fps), 'record_out' => to_frames(offset + duration, fps),
                 'mute' => false }
    else
      warn "  (ignoring unexpected spine element <#{el.name}>)"
    end
  end

  {
    'editor' => "Final Cut Pro (re-export #{doc.root.attributes['version']})",
    'timeline' => { 'frame_rate' => QaHarness.fps_value(fps), 'width' => seq_format[:width], 'height' => seq_format[:height],
                    'total_frames' => clips.map { |c| c['record_out'] }.max },
    'clips' => clips
  }
end

# ---------- System Events driving ----------

FIND_OUTLINE = <<~APPLESCRIPT
  on findOutline()
    tell application "System Events"
      tell process "Final Cut Pro"
        set queue to {window "Final Cut Pro"}
        repeat 400 times
          if (count of queue) is 0 then exit repeat
          set current to item 1 of queue
          set queue to rest of queue
          try
            if (role of current as string) is "AXOutline" then return current
            repeat with k in (every UI element of current)
              set end of queue to k
            end repeat
          end try
        end repeat
      end tell
    end tell
    return missing value
  end findOutline

  on rowLabel(theOutline, i)
    tell application "System Events"
      tell process "Final Cut Pro"
        set q2 to {row i of theOutline}
        repeat 30 times
          if (count of q2) is 0 then exit repeat
          set cur to item 1 of q2
          set q2 to rest of q2
          if (role of cur as string) is "AXTextField" then return (value of cur as string)
          try
            repeat with k in (every UI element of cur)
              set end of q2 to k
            end repeat
          end try
        end repeat
      end tell
    end tell
    return "?"
  end rowLabel
APPLESCRIPT

# Blind save-panel recipe (panels are remote views — not AX-readable): the
# filename field has focus when the panel opens; cmd+shift+G navigates.
def drive_save_panel(name:, dir:)
  QaHarness.osascript(<<~APPLESCRIPT)
    tell application "System Events"
      tell process "Final Cut Pro"
        set frontmost to true
        delay 0.5
        keystroke "a" using {command down}
        delay 0.3
        keystroke "#{name}"
        delay 0.5
        keystroke "g" using {command down, shift down}
        delay 1.0
        keystroke "#{dir}"
        delay 0.5
        key code 36
        delay 1.5
        key code 36
      end tell
    end tell
  APPLESCRIPT
end

def close_qa_library(name)
  out, = QaHarness.run_osascript(<<~APPLESCRIPT)
    #{FIND_OUTLINE}
    set theOutline to findOutline()
    if theOutline is missing value then return "NO OUTLINE"
    tell application "System Events"
      tell process "Final Cut Pro"
        set frontmost to true
        delay 0.5
        set n to count of rows of theOutline
        repeat with i from 1 to n
          if (my rowLabel(theOutline, i)) is "#{name}" then
            set value of attribute "AXSelected" of (row i of theOutline) to true
            delay 1.0
            try
              click menu item "Close Library “#{name}”" of menu "File" of menu bar 1
              return "CLOSED"
            on error errMsg
              return "MENU ERROR: " & errMsg
            end try
          end if
        end repeat
        return "NOT OPEN"
      end tell
    end tell
  APPLESCRIPT
  out
end

def selected_sidebar_row
  out, = QaHarness.run_osascript(<<~APPLESCRIPT)
    #{FIND_OUTLINE}
    set theOutline to findOutline()
    if theOutline is missing value then return "NO OUTLINE"
    tell application "System Events"
      tell process "Final Cut Pro"
        set n to count of rows of theOutline
        repeat with i from 1 to n
          if (value of attribute "AXSelected" of (row i of theOutline)) then
            return my rowLabel(theOutline, i)
          end if
        end repeat
      end tell
    end tell
    return "NONE"
  APPLESCRIPT
  out
end

def alert_texts
  out, = QaHarness.run_osascript(<<~APPLESCRIPT)
    tell application "System Events"
      tell process "Final Cut Pro"
        set report to {}
        repeat with w in windows
          if (subrole of w as string) is "AXDialog" and (name of w as string) is not "Final Cut Pro" then
            try
              set end of report to (name of w as string) & ": " & ((value of every static text of w) as string)
            end try
          end if
        end repeat
      end tell
    end tell
    set text item delimiters to " | "
    return report as string
  APPLESCRIPT
  out
end

# ---------- run ----------

event_name = first_event_name(xml_path)
bundle_path = File.join(FCP_WORK_DIR, "#{QA_LIBRARY}.fcpbundle")
reexport_path = File.join(FCP_WORK_DIR, "#{REEXPORT}.fcpxmld")
FileUtils.mkdir_p(FCP_WORK_DIR)

QaHarness.ensure_app_ready(process: 'Final Cut Pro', app_name: 'Final Cut Pro', ready_probe: <<~APPLESCRIPT)
  tell application "System Events" to tell process "Final Cut Pro"
    return exists menu "File" of menu bar 1
  end tell
APPLESCRIPT

# clean up any previous run (close in FCP before deleting on disk)
previous = close_qa_library(QA_LIBRARY)
puts "Previous QA library: #{previous}"
sleep 2 if previous == 'CLOSED' # let FCP release the bundle before it's deleted
FileUtils.rm_rf([bundle_path, reexport_path])

puts "Importing #{File.basename(xml_path)} into new library #{QA_LIBRARY}..."
system('open', '-a', 'Final Cut Pro', xml_path) || abort('open failed')

dialog_up = QaHarness.wait_until(tries: 30) do
  QaHarness.osascript_true?(<<~APPLESCRIPT)
    tell application "System Events" to tell process "Final Cut Pro"
      return exists window "Open Library"
    end tell
  APPLESCRIPT
end
abort "FCP never showed the 'Open Library' import dialog" unless dialog_up

QaHarness.osascript(<<~APPLESCRIPT)
  tell application "System Events"
    tell process "Final Cut Pro"
      set frontmost to true
      delay 0.5
      click button "New…" of window "Open Library"
    end tell
  end tell
APPLESCRIPT
sleep 1.5
drive_save_panel(name: QA_LIBRARY, dir: FCP_WORK_DIR)

event_dir = File.join(bundle_path, event_name)
unless QaHarness.wait_until(tries: 60) { File.directory?(event_dir) }
  alerts = alert_texts
  abort "Import didn't land (no #{event_dir}).#{alerts.empty? ? '' : " FCP alerts: #{alerts}"}"
end
puts "  ✓ event '#{event_name}' imported into #{File.basename(bundle_path)}"
sleep 3

alerts = alert_texts
abort "FCP raised an alert during import: #{alerts}" unless alerts.empty?

# FCP auto-selects the imported event
selection = selected_sidebar_row
unless selection == event_name
  abort "Expected sidebar selection '#{event_name}' after import, found '#{selection}' — not exporting blind"
end

puts 'Re-exporting the imported event as XML...'
QaHarness.osascript(<<~APPLESCRIPT)
  tell application "System Events"
    tell process "Final Cut Pro"
      set frontmost to true
      delay 0.5
      click menu item "Export XML…" of menu "File" of menu bar 1
    end tell
  end tell
APPLESCRIPT
sleep 2
drive_save_panel(name: REEXPORT, dir: FCP_WORK_DIR)

info_fcpxml   = File.join(reexport_path, 'Info.fcpxml')
bare_reexport = File.join(FCP_WORK_DIR, "#{REEXPORT}.fcpxml")
landed = QaHarness.wait_until(tries: 30) { File.exist?(info_fcpxml) || File.exist?(bare_reexport) }
abort 'Re-export never appeared on disk' unless landed
reexport_file = File.exist?(info_fcpxml) ? reexport_path : bare_reexport

actual = parse_fcp_reexport(reexport_file)
puts "Closing QA library: #{close_qa_library(QA_LIBRARY)}"
QaHarness.finish!(actual, xml_path: xml_path, expected_path: expected_path,
                  label: "Final Cut Pro round-trip of #{File.basename(xml_path)}")
