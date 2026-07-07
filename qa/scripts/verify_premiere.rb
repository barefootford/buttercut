# frozen_string_literal: true

# Premiere leg of the editor round-trip QA harness: launches Premiere with a
# startup ExtendScript (the only unattended script mechanism Premiere offers)
# that imports the ButterCut FCP7 XML into a scratch project, walks the
# sequence's tracks, and writes a tick-accurate JSON report; this runner then
# verifies it frame-accurately against the fixture's expected_<scenario>.json.
#
# ExtendScript is supported through ~Sept 2026; the replacement is a UXP panel
# (no unattended loader exists yet — see qa/editor-roundtrip.md, Premiere notes).
#
# Usage (from the repo root; Premiere must NOT already be running):
#   ruby qa/scripts/verify_premiere.rb [xml_path] [expected_json_path]
#
# The runner launches its own Premiere instance and force-quits it when done
# (the script closes the scratch project first, so nothing is left dirty). If
# Premiere is already running it aborts rather than risk someone's open work.

require 'fileutils'
require 'json'
require_relative 'qa_helpers'

TICKS_PER_SECOND = 254_016_000_000
TEMPLATE     = File.join(__dir__, 'premiere', 'buttercut_qa_dump.jsx.template')
JSX_PATH     = '/tmp/buttercut_qa_premiere_dump.jsx'
REPORT_PATH  = '/tmp/buttercut_qa_premiere_report.json'
PROJECT_PATH = '/tmp/buttercut_qa_premiere_scratch.prproj'

def kill_premiere = system('pkill', '-9', '-f', 'Adobe Premiere', out: File::NULL, err: File::NULL)

xml_path, expected_path = QaHarness.verify_args('premiere')

premiere_bin = QaHarness.premiere_binary
abort 'No Adobe Premiere binary found under /Applications' unless premiere_bin

if system('pgrep -fq "Adobe Premiere"')
  abort 'Adobe Premiere is already running — quit it first (the QA runner must launch its own instance ' \
        'because Premiere only executes scripts at launch).'
end

jsx = File.read(TEMPLATE)
      .gsub('__XML_PATH__', xml_path)
      .gsub('__REPORT_PATH__', REPORT_PATH)
      .gsub('__PROJECT_PATH__', PROJECT_PATH)
File.write(JSX_PATH, jsx)
FileUtils.rm_f([REPORT_PATH, "#{REPORT_PATH}.tmp", PROJECT_PATH])

puts "Launching #{File.basename(premiere_bin)} with startup script (this takes a minute)..."
pid = Process.spawn(premiere_bin, '/C', "es.processFile #{JSX_PATH}", %i[out err] => '/dev/null')
Process.detach(pid)

unless QaHarness.wait_until(tries: 150, interval: 2) { File.exist?(REPORT_PATH) }
  kill_premiere
  abort "No report at #{REPORT_PATH} after 5 minutes — the /C es.processFile launch flag may have " \
        'stopped working in this Premiere version, or a first-run dialog blocked startup. ' \
        'See the Premiere notes in qa/editor-roundtrip.md for the fallback.'
end

# the jsx writes the report atomically (tmp + rename), so it's complete once it exists
report = JSON.parse(File.read(REPORT_PATH))

kill_premiere
FileUtils.rm_f(PROJECT_PATH)

abort "Premiere script failed at stage '#{report['stage']}': #{report['error']}" unless report['ok']

sequence = report.fetch('sequence')
ticks_per_frame = Integer(sequence.fetch('timebase_ticks_per_frame'))
# Exact even for NTSC: 254,016,000,000 ticks/s over 8,475,667,200 ticks/frame
# reduces to 30000/1001.
fps = QaHarness.fps_value(Rational(TICKS_PER_SECOND, ticks_per_frame))

def ticks_to_frames(ticks, ticks_per_frame)
  t = Integer(ticks)
  raise "#{t} ticks is not frame-aligned (#{ticks_per_frame} ticks/frame)" unless (t % ticks_per_frame).zero?

  t / ticks_per_frame
end

video_items = report.fetch('video_tracks').flat_map { |t| t['items'] }
clips = video_items.map do |item|
  basename = File.basename(item['media_path'] || item['name'].to_s)
  type = Library.media_type_of(basename) || 'video' # lib's registry, with its lenient-read video fallback
  image = type == 'image'
  clip = {
    'source' => basename,
    'type' => type,
    'record_in' => ticks_to_frames(item['start_ticks'], ticks_per_frame),
    'record_out' => ticks_to_frames(item['end_ticks'], ticks_per_frame)
  }
  unless image
    clip['source_in']  = ticks_to_frames(item['in_ticks'], ticks_per_frame)
    clip['source_out'] = ticks_to_frames(item['out_ticks'], ticks_per_frame)
  end
  clip # mute isn't exposed to ExtendScript — compare_timeline reports it as skipped
end

actual = {
  'editor' => "Adobe Premiere #{report['app_version']}",
  'timeline' => {
    'frame_rate' => fps,
    'width' => sequence['width'],
    'height' => sequence['height'],
    'total_frames' => clips.map { |c| c['record_out'] }.max
  },
  'clips' => clips
}

QaHarness.finish!(actual, xml_path: xml_path, expected_path: expected_path,
                  label: "Premiere import of #{File.basename(xml_path)}")
