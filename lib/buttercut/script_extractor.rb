#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract a clean dialogue script from an audio transcript JSON and print
# it to stdout. Strips word-level timing, segment timestamps, and metadata
# — just the spoken text, one segment per line. Agents that want dialogue
# read this on demand instead of a pre-baked file, so the transcript JSON
# stays the single source of truth and there's no script-vs-transcript
# drift. Pipe to a file if you need a copy on disk.
#
# Usage:
#   ruby script_extractor.rb <audio_transcript.json>            # → stdout
#   ruby script_extractor.rb <audio_transcript.json> > out.txt  # → file

require 'json'

class ScriptExtractor
  def self.extract(transcript_path)
    new(transcript_path).extract
  end

  def initialize(transcript_path)
    raise ArgumentError, 'transcript_path is required' if transcript_path.nil? || transcript_path.empty?
    raise ArgumentError, "transcript not found: #{transcript_path}" unless File.exist?(transcript_path)

    @transcript_path = transcript_path
  end

  def extract
    $stdout.write(script)
  end

  private

  attr_reader :transcript_path

  def data
    @data ||= JSON.parse(File.read(transcript_path, encoding: 'UTF-8'))
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
  transcript_path = ARGV.first
  abort('usage: script_extractor.rb <audio_transcript.json>') unless transcript_path

  ScriptExtractor.extract(transcript_path)
end
