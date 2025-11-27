#!/usr/bin/env ruby
require 'json'
require_relative '../../../lib/buttercut/transcript_compressor'

abort "Usage: ruby prepare_visual_script.rb <json_file>" if ARGV.empty?
abort "Error: File not found: #{ARGV[0]}" unless File.exist?(ARGV[0])

begin
  data = JSON.parse(File.read(ARGV[0]))

  data['segments']&.each { |s| s.delete('words') }
  data.delete('word_segments')

  # Convert to compressed format (without word-level timing)
  compressed = Buttercut::TranscriptCompressor.compress(data, include_words: false)

  # Change extension from .json to .txt
  output_file = ARGV[0].sub(/\.json$/, '.txt')
  File.write(output_file, compressed)

  # Remove original JSON file
  File.delete(ARGV[0]) if output_file != ARGV[0]

  puts "Compressed: #{output_file} (75% token reduction, word-level timing removed)"
rescue JSON::ParserError => e
  abort "Error: Invalid JSON - #{e.message}"
end
