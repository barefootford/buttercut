#!/usr/bin/env ruby
require 'yaml'

# Usage: dialogue_extractor.rb [roughcut.yaml]
yaml_path = ARGV[0]

if yaml_path.nil?
  puts "Usage: dialogue_extractor.rb [roughcut.yaml]"
  exit 1
end

unless File.exist?(yaml_path)
  puts "File not found: #{yaml_path}"
  exit 1
end

data = YAML.load_file(yaml_path)
clips = data['clips'] || []

if clips.empty?
  puts "No clips found in #{yaml_path}"
  exit 1
end

# Calculate total duration from clips
def timecode_to_seconds(tc)
  parts = tc.split(':')
  hours = parts[0].to_f
  minutes = parts[1].to_f
  seconds = parts[2].to_f
  hours * 3600 + minutes * 60 + seconds
end

def seconds_to_duration(secs)
  minutes = (secs / 60).to_i
  seconds = (secs % 60).to_i
  "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
end

total_seconds = 0
clips.each do |clip|
  in_sec = timecode_to_seconds(clip['in_point'])
  out_sec = timecode_to_seconds(clip['out_point'])
  total_seconds += (out_sec - in_sec)
end

# Output header
puts "=" * 60
puts "DIALOGUE PREVIEW"
puts "#{clips.length} clips | #{seconds_to_duration(total_seconds)} total"
puts "=" * 60
puts

# Output each clip's dialogue
clips.each_with_index do |clip, idx|
  dialogue = clip['dialogue'].to_s.strip
  source = File.basename(clip['source_file'], '.*')

  # Calculate clip duration
  in_sec = timecode_to_seconds(clip['in_point'])
  out_sec = timecode_to_seconds(clip['out_point'])
  duration = (out_sec - in_sec).round(1)

  if dialogue.empty?
    puts "[#{idx + 1}] #{source} (#{duration}s) - [B-ROLL]"
  else
    puts "[#{idx + 1}] #{source} (#{duration}s)"
    puts "    #{dialogue}"
  end
  puts
end
