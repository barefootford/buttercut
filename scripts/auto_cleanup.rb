#!/usr/bin/env ruby
# Automatically remove pauses and stumbles from a WhisperX transcript.
#
# Usage:
#   ruby scripts/auto_cleanup.rb <transcript.json> <source_filename> <output.yaml>
#
# transcript.json  - output of skills/transcribe-audio/prepare_audio_script.rb
# source_filename  - basename of the video file (e.g. IMG_0713.MOV)
# output.yaml      - where to write the roughcut YAML

require 'json'
require 'yaml'
require 'time'

PAUSE_THRESHOLD = (ENV['PAUSE_THRESHOLD'] || 0.5).to_f
MERGE_THRESHOLD = (ENV['MERGE_THRESHOLD'] || 0.1).to_f
MIN_DURATION    = (ENV['MIN_DURATION']    || 0.3).to_f

# Words that are always treated as standalone fillers and removed.
# Case-insensitive match against the bare word (punctuation stripped).
FILLER_WORDS = %w[
  äh ähm hmm hm mhm
].freeze

# Words removed only when they appear at the very start of a keep-segment
# (common German sentence-starters that pad but don't add meaning).
LEADING_FILLERS = %w[
  also halt naja
].freeze

def format_timecode(seconds)
  h = (seconds / 3600).to_i
  m = ((seconds % 3600) / 60).to_i
  s = seconds % 60
  format('%02d:%02d:%05.2f', h, m, s)
end

def normalize(word)
  word.downcase.gsub(/[^a-zäöüß]/, '')
end

def filler?(word)
  FILLER_WORDS.include?(normalize(word))
end

def stumble?(words, index)
  return false if index.zero?
  normalize(words[index]) == normalize(words[index - 1])
end

transcript_path = ARGV[0]
source_file     = ARGV[1]
output_path     = ARGV[2]

if ARGV.length != 3
  warn "Usage: #{$PROGRAM_NAME} <transcript.json> <source_filename> <output.yaml>"
  exit 1
end

abort "Transcript not found: #{transcript_path}" unless File.exist?(transcript_path)

data     = JSON.parse(File.read(transcript_path))
segments = data['segments'] || []

# Flatten all words across all segments into one ordered list.
all_words = segments.flat_map { |seg| seg['words'] || [] }

if all_words.empty?
  abort 'No word-level timing found in transcript. Re-run WhisperX with --word_timestamps True.'
end

puts "Loaded #{all_words.length} words from transcript."

# Build keep-segments by walking the word list and splitting on cut points.
keep_segments = []
current = []

all_words.each_with_index do |word, i|
  w = word['word'].to_s.strip
  t_start = word['start'].to_f
  t_end   = word['end'].to_f

  # Cut on filler words — don't include them at all.
  if filler?(w)
    keep_segments << current unless current.empty?
    current = []
    next
  end

  # Cut on consecutive repeated words (stumble).
  if !current.empty? && stumble?(all_words.map { |x| x['word'].to_s }, i)
    # Drop the repeated word; keep the segment running.
    next
  end

  # Cut on long pause before this word.
  unless current.empty?
    prev_end = current.last['end'].to_f
    if t_start - prev_end > PAUSE_THRESHOLD
      keep_segments << current
      current = []
    end
  end

  current << word
end
keep_segments << current unless current.empty?

puts "Found #{keep_segments.length} raw segments after cuts."

# Merge segments separated by less than MERGE_THRESHOLD.
merged = []
keep_segments.each do |seg|
  next if seg.empty?

  if merged.empty?
    merged << seg
  elsif seg.first['start'].to_f - merged.last.last['end'].to_f < MERGE_THRESHOLD
    merged[-1] = merged.last + seg
  else
    merged << seg
  end
end

puts "After merging: #{merged.length} segments."

# Drop leading fillers at the start of each segment.
merged.each do |seg|
  seg.shift while !seg.empty? && LEADING_FILLERS.include?(normalize(seg.first['word'].to_s))
  seg.pop   while !seg.empty? && LEADING_FILLERS.include?(normalize(seg.last['word'].to_s))
end

# Filter out segments shorter than MIN_DURATION.
final = merged.reject do |seg|
  seg.empty? || (seg.last['end'].to_f - seg.first['start'].to_f) < MIN_DURATION
end

puts "After duration filter: #{final.length} segments kept."

# Build roughcut YAML clips.
clips = final.map do |seg|
  in_pt  = seg.first['start'].to_f
  out_pt = seg.last['end'].to_f
  text   = seg.map { |w| w['word'].to_s.strip }.join(' ')

  {
    'source_file'        => source_file,
    'in_point'           => format_timecode(in_pt),
    'out_point'          => format_timecode(out_pt),
    'dialogue'           => text,
    'visual_description' => ''
  }
end

total_duration = clips.sum do |c|
  in_s  = c['in_point'].split(':').then  { |h, m, s| h.to_i * 3600 + m.to_i * 60 + s.to_f }
  out_s = c['out_point'].split(':').then { |h, m, s| h.to_i * 3600 + m.to_i * 60 + s.to_f }
  out_s - in_s
end

roughcut = {
  'description' => "Auto-cleanup of #{source_file} — pauses and stumbles removed",
  'clips'       => clips,
  'metadata'    => {
    'created_date'   => Time.now.strftime('%Y-%m-%d'),
    'total_duration' => format_timecode(total_duration)
  }
}

File.write(output_path, roughcut.to_yaml)

puts "\nDone."
puts "  Clips:          #{clips.length}"
puts "  Total duration: #{format_timecode(total_duration)}"
puts "  Output:         #{output_path}"
