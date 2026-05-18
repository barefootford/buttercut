#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract a clean dialogue script from an audio transcript JSON.
# Strips word-level timing, segment timestamps, and metadata — just the
# spoken text, one segment per line. The roughcut agent reads this when it
# needs the dialogue without the token weight of the full JSON.
#
# Usage:
#   ruby script_extractor.rb <audio_transcript.json> <output_script.txt>

require 'json'
require 'fileutils'

class ScriptExtractor
  def self.extract(transcript_path, output_path)
    new(transcript_path, output_path).extract
  end

  def initialize(transcript_path, output_path)
    raise ArgumentError, 'transcript_path is required' if transcript_path.nil? || transcript_path.empty?
    raise ArgumentError, 'output_path is required' if output_path.nil? || output_path.empty?
    raise ArgumentError, "transcript not found: #{transcript_path}" unless File.exist?(transcript_path)

    @transcript_path = transcript_path
    @output_path = output_path
  end

  def extract
    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, script)
    puts "script: #{output_path}"
  end

  private

  attr_reader :transcript_path, :output_path

  def data
    @data ||= JSON.parse(File.read(transcript_path))
  end

  def segments
    data['segments'] or raise "transcript JSON has no 'segments' key: #{transcript_path}"
  end

  def script
    lines = segments.filter_map do |segment|
      text = segment['text'].to_s.strip
      text.empty? ? nil : text
    end
    "#{lines.join("\n")}\n"
  end
end

if __FILE__ == $PROGRAM_NAME
  transcript_path, output_path = ARGV
  abort('usage: script_extractor.rb <audio_transcript.json> <output_script.txt>') unless transcript_path && output_path

  ScriptExtractor.extract(transcript_path, output_path)
end
