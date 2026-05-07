#!/usr/bin/env ruby
require 'json'

abort "Usage: ruby prepare_visual_script.rb <json_file>" if ARGV.empty?
abort "Error: File not found: #{ARGV[0]}" unless File.exist?(ARGV[0])

begin
  data = JSON.parse(File.read(ARGV[0]))

  data['segments']&.each { |s| s.delete('words') }
  data.delete('word_segments')

  # Reorder keys: language and video_path first, then segments, then everything else
  reordered = {}
  reordered['language'] = data['language'] if data['language']
  reordered['video_path'] = data['video_path'] if data['video_path']
  reordered['segments'] = data['segments'] if data['segments']
  # Add any other keys that might exist
  data.each { |k, v| reordered[k] = v unless reordered.key?(k) }

  File.write(ARGV[0], JSON.pretty_generate(reordered))
  puts "Prettified: #{ARGV[0]} (word-level timing removed)"
rescue JSON::ParserError => e
  abort "Error: Invalid JSON - #{e.message}"
end
