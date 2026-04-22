#!/usr/bin/env ruby
# Extract the plain-text script from a WhisperX-style transcript JSON.
#
# Usage:
#   ruby .claude/scripts/script_extractor.rb <transcript.json> <output.txt>
#
# Output is one segment per paragraph (blank line between), trimmed, suitable
# for proofreading by a human or a sub-agent without the overhead of the full
# transcript JSON (word-level timing, scores, etc.).

require 'json'

class ScriptExtractor
  def self.extract(transcript_path, output_path)
    new(transcript_path, output_path).extract
  end

  def initialize(transcript_path, output_path)
    raise ArgumentError, "transcript_path is required" if transcript_path.nil? || transcript_path.empty?
    raise ArgumentError, "output_path is required" if output_path.nil? || output_path.empty?
    @transcript_path = transcript_path
    @output_path = output_path
  end

  def extract
    write_output(format_script)
    report
  end

  private

  attr_reader :transcript_path, :output_path

  def data
    @data ||= JSON.parse(File.read(transcript_path))
  end

  def segments
    data["segments"] or raise "transcript JSON has no 'segments' key: #{transcript_path}"
  end

  def format_script
    paragraphs = segments.map { |s| s["text"].to_s.strip }.reject(&:empty?)
    paragraphs.join("\n\n") + "\n"
  end

  def write_output(text)
    File.write(output_path, text)
  end

  def report
    in_kb = (File.size(transcript_path) / 1024.0).round(1)
    out_kb = (File.size(output_path) / 1024.0).round(1)
    puts "Extracted script: #{output_path} (#{out_kb} KB from #{in_kb} KB source, #{segments.size} segments)"
  end
end

if __FILE__ == $PROGRAM_NAME
  transcript_path, output_path = ARGV
  abort("usage: script_extractor.rb <transcript.json> <output.txt>") unless transcript_path && output_path
  abort("file not found: #{transcript_path}") unless File.file?(transcript_path)
  if File.expand_path(output_path) == File.expand_path(transcript_path)
    abort("output path must differ from transcript path: #{transcript_path}")
  end
  ScriptExtractor.extract(transcript_path, output_path)
end
