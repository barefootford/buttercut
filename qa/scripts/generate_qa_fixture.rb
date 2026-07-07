# frozen_string_literal: true

# Generates the editor round-trip QA fixture: a throwaway library
# (libraries/qa-editor-roundtrip/) holding synthetic, self-identifying footage,
# one cut per scenario, and the ground-truth files the verifiers compare
# against.
#
# The media identifies itself frame-by-frame — that's the whole trick. Each
# video burns its clip letter, source timecode, and source frame number into
# every frame, over a solid color unique to the clip, with a per-second beep
# pattern unique to the clip (so waveforms are tellable apart on sight). A
# timeline position can therefore be verified against what the editor actually
# shows, not against metadata that could be wrong in the same way twice.
#
# Everything derives from the literal tables below (MEDIA_SPECS, SCENARIOS).
# Trims are written in FRAMES — the native unit — and every expected-timeline
# number is computed here with plain integer/rational arithmetic, deliberately
# NOT with lib/buttercut's timecode math, so an exporter bug can't cancel
# itself out in the expectation.
#
# Usage (from the repo root, either edition):
#   ruby qa/scripts/generate_qa_fixture.rb
#
# Idempotent: an existing qa-editor-roundtrip library is deleted and rebuilt
# (only when its sentinel file proves we generated it).

require 'fileutils'
require 'json'
require 'yaml'
require_relative 'qa_helpers'
require_relative '../../lib/buttercut/media_tools'

LIBRARY_DIR = QaHarness::FIXTURE_DIR
MEDIA_DIR   = File.join(LIBRARY_DIR, 'media')
SENTINEL    = File.join(LIBRARY_DIR, '.generated-by-buttercut-qa')
FONT        = File.expand_path('../../lib/buttercut/Arimo-Regular.ttf', __dir__)

CLIP_SECONDS = 24
SIZE = { width: 1280, height: 720 }.freeze

# The per-second beep signatures (aevalsrc gate expressions on mod(t,1)) —
# the audible/visible-in-waveform fingerprint each clip reuses with its own
# frequency.
ONE_SHORT = ['lt(mod(t,1),0.12)', 'one short beep per second'].freeze
TWO_SHORT = ['(lt(mod(t,1),0.08)+gt(mod(t,1),0.2)*lt(mod(t,1),0.28))', 'two short beeps per second'].freeze
ONE_LONG  = ['lt(mod(t,1),0.4)', 'one long beep per second'].freeze

# One entry per synthetic source file. `rate` is the exact frame rate the
# clip is encoded at; `timecode` (optional) is burned into the container as
# the SMPTE start timecode — a ";" separator marks drop-frame numbering.
MEDIA_SPECS = {
  'qa_clipA.mov' => { color: 'red',     letter: 'A', freq: 440, beep: ONE_SHORT, rate: '30/1' },
  'qa_clipB.mov' => { color: 'green',   letter: 'B', freq: 660, beep: TWO_SHORT, rate: '30/1' },
  'qa_clipC.mov' => { color: 'blue',    letter: 'C', freq: 880, beep: ONE_LONG,  rate: '30/1' },
  # NTSC 29.97: D's drop-frame timecode starts 2 frames before the 01:00:00
  # skip boundary, so its digits cross a drop; E is NDF at the same rate.
  'qa_ntscD.mov' => { color: 'purple',  letter: 'D', freq: 520, beep: ONE_SHORT, rate: '30000/1001', timecode: '00:59:59;28' },
  'qa_ntscE.mov' => { color: 'teal',    letter: 'E', freq: 700, beep: TWO_SHORT, rate: '30000/1001', timecode: '01:00:00:00' },
  # 23.976 film rate: F carries an embedded SMPTE start (the real-world value
  # from spec/fixtures/media/P1044376_timecode_fixture.mov); G has none, so
  # the zero-base path runs at a fractional rate too.
  'qa_filmF.mov' => { color: 'orange',  letter: 'F', freq: 480, beep: ONE_LONG,  rate: '24000/1001', timecode: '21:44:10:09' },
  'qa_filmG.mov' => { color: 'magenta', letter: 'G', freq: 760, beep: ONE_SHORT, rate: '24000/1001' }
}.freeze
TITLE_CARD = 'qa_title_card.png'
TITLE_CARD_SPEC = { color: 'yellow', text: 'TITLE CARD' }.freeze

# The scenario cuts, in timeline order. Video trims are `in:`/`out:` in
# SOURCE FRAMES; stills use `frames:` at the timeline rate. Every scenario
# currently uses sources at the timeline's own rate (mixed-rate conform is a
# future scenario with its own expected-behavior decision).
SCENARIOS = {
  'canonical-30' => {
    rate: '30/1',
    clips: [
      { source: 'qa_clipB.mov', in: 300, out: 480 },
      { source: 'qa_clipA.mov', in: 60,  out: 180, mute: true },
      { source: TITLE_CARD,     frames: 150 },
      { source: 'qa_clipC.mov', in: 15,  out: 255 }
    ]
  },
  'ntsc-2997-df' => {
    rate: '30000/1001',
    clips: [
      { source: 'qa_ntscD.mov', in: 30,  out: 210 },
      { source: 'qa_ntscE.mov', in: 120, out: 300, mute: true },
      { source: 'qa_ntscD.mov', in: 450, out: 600 }
    ]
  },
  'film-23976' => {
    rate: '24000/1001',
    clips: [
      { source: 'qa_filmF.mov', in: 48,  out: 240 },
      { source: 'qa_filmG.mov', in: 0,   out: 120 },
      { source: 'qa_filmF.mov', in: 360, out: 480 }
    ]
  }
}.freeze

unless SCENARIOS.keys.sort == QaHarness::SCENARIOS.keys.sort
  abort "SCENARIOS here (#{SCENARIOS.keys.sort.join(', ')}) must match QaHarness::SCENARIOS " \
        "(#{QaHarness::SCENARIOS.keys.sort.join(', ')})"
end

def rate_rational(rate) = Rational(*rate.split('/').map(&:to_i))

def frames_to_seconds(frames, rate) = frames / rate_rational(rate)

def hms(seconds)
  whole = seconds.to_i
  format('%02d:%02d:%09.6f', whole / 3600, (whole % 3600) / 60, (seconds % 60).to_f)
end

def run!(*cmd)
  puts "  $ #{cmd.join(' ')[0, 160]}"
  system(*cmd, exception: true)
end

# A scenario's clips enriched with frame counts and timeline positions,
# computed once (plain arithmetic — see header) and shared by the cut,
# expected-timeline, and expected-visuals sections below.
def clip_rows(scenario)
  cursor = 0
  scenario[:clips].map do |clip|
    unless clip[:frames] # video
      spec = MEDIA_SPECS.fetch(clip[:source])
      unless spec[:rate] == scenario[:rate]
        abort "#{clip[:source]} is #{spec[:rate]} on a #{scenario[:rate]} timeline — " \
              'same-rate sources only until the mixed-rate scenario lands'
      end
    end
    frames = clip[:frames] || (clip[:out] - clip[:in])
    row = clip.merge(frame_count: frames, record_in: cursor, record_out: cursor + frames)
    cursor += frames
    row
  end
end

# ---------- 1. reset the fixture library ----------
if File.exist?(LIBRARY_DIR)
  unless File.exist?(SENTINEL)
    abort "Refusing to delete #{LIBRARY_DIR}: no #{File.basename(SENTINEL)} sentinel. " \
          'If this library is yours, remove it manually and re-run.'
  end
  FileUtils.rm_rf(LIBRARY_DIR)
end

puts "Creating library #{QaHarness::LIBRARY_NAME}..."
Library.create(QaHarness::LIBRARY_NAME, language: 'en', editor: 'fcpx', transcript_refinement: false, media_paths: [])
FileUtils.mkdir_p(MEDIA_DIR)
File.write(SENTINEL, "Generated by qa/scripts/generate_qa_fixture.rb — safe to delete.\n")

# ---------- 2. synthesize self-identifying media ----------
abort "Font not found at #{FONT}" unless File.exist?(FONT)

MEDIA_SPECS.each do |filename, spec|
  beep_expr, beep_desc = spec[:beep]
  puts "Generating #{filename} (#{spec[:color]}, '#{spec[:letter]}', #{spec[:rate]}#{spec[:timecode] ? ", tc #{spec[:timecode]}" : ''}, #{beep_desc})..."
  big    = "drawtext=fontfile=#{FONT}:text='#{spec[:letter]}':fontsize=360:fontcolor=white@0.9:" \
           'x=(w-tw)/2:y=(h-th)/2-60'
  ticker = "drawtext=fontfile=#{FONT}:text='#{spec[:letter]} SRC %{pts\\:hms} F%{n}':fontsize=56:fontcolor=white:" \
           'x=(w-tw)/2:y=h-th-32:box=1:boxcolor=black@0.65:boxborderw=12'
  audio  = "aevalsrc=exprs='sin(2*PI*#{spec[:freq]}*t)*0.6*#{beep_expr}':sample_rate=48000:duration=#{CLIP_SECONDS}"
  timecode_args = spec[:timecode] ? ['-timecode', spec[:timecode]] : []

  run!(MediaTools.ffmpeg, '-y', '-loglevel', 'error',
       '-f', 'lavfi', '-i', "color=c=#{spec[:color]}:size=#{SIZE[:width]}x#{SIZE[:height]}:rate=#{spec[:rate]}:duration=#{CLIP_SECONDS}",
       '-f', 'lavfi', '-i', audio,
       '-vf', "#{big},#{ticker}",
       '-af', 'pan=stereo|c0=c0|c1=c0',
       '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-crf', '18',
       *timecode_args,
       '-c:a', 'pcm_s16le', '-shortest', File.join(MEDIA_DIR, filename))
end

puts "Generating #{TITLE_CARD} (#{TITLE_CARD_SPEC[:color]} still)..."
run!(MediaTools.ffmpeg, '-y', '-loglevel', 'error',
     '-f', 'lavfi', '-i', "color=c=#{TITLE_CARD_SPEC[:color]}:size=#{SIZE[:width]}x#{SIZE[:height]}",
     '-vf', "drawtext=fontfile=#{FONT}:text='#{TITLE_CARD_SPEC[:text]}':fontsize=140:fontcolor=black:x=(w-tw)/2:y=(h-th)/2",
     '-frames:v', '1', File.join(MEDIA_DIR, TITLE_CARD))

library = Library.find(QaHarness::LIBRARY_NAME)
library.add_media((MEDIA_SPECS.keys + [TITLE_CARD]).map { |f| File.join(MEDIA_DIR, f) })

# ---------- 3. per-scenario cut, expected timeline, expected visuals ----------
visuals = +<<~HEADER
  # Expected visuals — #{QaHarness::LIBRARY_NAME}

  What a correctly imported timeline shows at each position. `SRC` is the
  burned-in media-relative ticker (`F<n>` = source frame number); it must match
  the source trim frame-accurately regardless of any embedded start timecode.
HEADER

SCENARIOS.each do |name, scenario|
  rate = scenario[:rate]
  rational = rate_rational(rate)
  rows = clip_rows(scenario)
  total_frames = rows.last[:record_out]
  rate_value = QaHarness.fps_value(rational)

  cut_clips = rows.map do |row|
    if row[:frames] # still image
      { 'source_file' => row[:source], 'duration' => hms(frames_to_seconds(row[:frames], rate)),
        'dialogue' => '',
        'visual_description' => "[#{TITLE_CARD_SPEC[:color].capitalize} title card reading #{TITLE_CARD_SPEC[:text]}]" }
    else
      spec = MEDIA_SPECS.fetch(row[:source])
      entry = { 'source_file' => row[:source],
                'in_point' => hms(frames_to_seconds(row[:in], rate)),
                'out_point' => hms(frames_to_seconds(row[:out], rate)),
                'dialogue' => '',
                'visual_description' => "[Solid #{spec[:color]} frame, giant letter #{spec[:letter]}, " \
                                        'source timecode/frame ticker along the bottom]' }
      entry['mute'] = true if row[:mute]
      entry
    end
  end

  cut = {
    'description' => "QA editor round-trip scenario #{name} — see qa/editor-roundtrip.md",
    # the cut carries the exact rate string ("30000/1001") for fractional
    # rates; expected JSON carries the decimal editors report back
    'timeline' => { 'frame_rate' => rational.denominator == 1 ? rational.to_i : rate,
                    'width' => SIZE[:width], 'height' => SIZE[:height] },
    'clips' => cut_clips,
    'metadata' => { 'created_date' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
                    'total_duration' => hms(frames_to_seconds(total_frames, rate)) }
  }
  File.write(QaHarness.cut_yaml(name), cut.to_yaml)

  expected_clips = rows.each_with_index.map do |row, i|
    entry = {
      'n' => i + 1,
      'source' => row[:source],
      'type' => row[:frames] ? 'image' : 'video',
      'record_in' => row[:record_in],
      'record_out' => row[:record_out],
      'mute' => !!row[:mute]
    }
    unless row[:frames]
      entry['source_in']  = row[:in]
      entry['source_out'] = row[:out]
    end
    entry
  end

  expected = {
    'fixture' => QaHarness::LIBRARY_NAME,
    'scenario' => name,
    'generated_at' => Time.now.strftime('%Y-%m-%dT%H:%M:%S'),
    'timeline' => { 'frame_rate' => rate_value, 'width' => SIZE[:width], 'height' => SIZE[:height],
                    'total_frames' => total_frames },
    'media_dir' => MEDIA_DIR,
    'clips' => expected_clips
  }
  File.write(QaHarness.expected_json(name), JSON.pretty_generate(expected) + "\n")

  visuals << "\n## #{name} (#{rate_value} fps, #{total_frames} frames)\n\n"
  visuals << "| Timeline frames | Clip | Screen | SRC ticker frames | Audio / waveform |\n"
  visuals << "|---|---|---|---|---|\n"
  rows.each do |row|
    row_range = "#{row[:record_in]}–#{row[:record_out]}"
    if row[:frames]
      visuals << "| #{row_range} | #{row[:source]} | #{TITLE_CARD_SPEC[:color]} #{TITLE_CARD_SPEC[:text]} | — | silence |\n"
    else
      spec = MEDIA_SPECS.fetch(row[:source])
      _, beep_desc = spec[:beep]
      audio = row[:mute] ? "MUTED — flat/no waveform (source had #{beep_desc})" : "#{beep_desc} (#{spec[:freq]} Hz)"
      visuals << "| #{row_range} | #{row[:source]} | solid #{spec[:color]}, giant #{spec[:letter]} | F#{row[:in]} → F#{row[:out]} | #{audio} |\n"
    end
  end
end

File.write(File.join(LIBRARY_DIR, 'expected_visuals.md'), visuals)

puts <<~DONE

  ✓ Fixture ready.
    Library:   #{LIBRARY_DIR}
    Scenarios: #{SCENARIOS.keys.join(', ')}
    Cuts:      #{QaHarness::CUTS_DIR}/<scenario>.yaml
    Expected:  #{LIBRARY_DIR}/expected_<scenario>.json

  Run the suite (from the repo root):
    ruby qa/scripts/run_all.rb            # fast tier (canonical scenario)
    ruby qa/scripts/run_all.rb --full     # every scenario
DONE
