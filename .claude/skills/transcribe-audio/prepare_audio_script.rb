#!/usr/bin/env ruby
require 'json'
require_relative '../../../lib/buttercut/transcript_compressor'

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

  # Add video source path as metadata
  json_data['video_path'] = video_path

  # Remove "score" from words array to slim down file size
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

  # Convert to compressed format
  compressed = Buttercut::TranscriptCompressor.compress(json_data, include_words: true)

  # Change extension from .json to .txt
  output_file = input_file.sub(/\.json$/, '.txt')
  File.write(output_file, compressed)

  # Remove original JSON file
  File.delete(input_file) if output_file != input_file

  puts "Compressed: #{output_file} (75% token reduction, video path added)"
rescue JSON::ParserError => e
  puts "Error: Invalid JSON in #{input_file}"
  puts e.message
  exit 1
end
