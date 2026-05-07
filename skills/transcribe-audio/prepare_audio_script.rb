#!/usr/bin/env ruby
require 'json'

if ARGV.length < 2
  puts "Usage: ruby prepare_audio_script.rb <json_file> <video_filepath>"
  exit 1
end

input_file = ARGV[0]
video_path = ARGV[1]

unless File.exist?(input_file)
  puts "Error: File not found: #{input_file}"
  exit 1
end

begin
  json_data = JSON.parse(File.read(input_file))

  # Add video source path as metadata at the top
  json_data['video_path'] = video_path

  # Remove "score" from words array to slim down file size
  # Keep "end" times in both segments and words for accurate rough cut timecoding
  if json_data['segments']
    json_data['segments'].each do |segment|
      if segment['words']
        segment['words'].each do |word|
          word.delete('score')
        end
      end
    end
  end

  # Also remove from word_segments if present
  if json_data['word_segments']
    json_data['word_segments'].each do |word|
      word.delete('score')
    end
  end

  File.write(input_file, JSON.pretty_generate(json_data))
  puts "Prettified: #{input_file} (video path added, scores removed)"
rescue JSON::ParserError => e
  puts "Error: Invalid JSON in #{input_file}"
  puts e.message
  exit 1
end
