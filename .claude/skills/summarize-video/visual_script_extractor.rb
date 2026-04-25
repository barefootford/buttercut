#!/usr/bin/env ruby
# Extract a human-readable script from a visual transcript JSON,
# interleaving [VISUAL] descriptions with timestamped dialogue.
# Prints to stdout for direct consumption by the summarize-video skill.
#
# Usage:
#   ruby visual_script_extractor.rb <visual_transcript.json>

require 'json'

class VisualScriptExtractor
  def self.extract(transcript_path)
    new(transcript_path).extract
  end

  def initialize(transcript_path)
    raise ArgumentError, "transcript_path is required" if transcript_path.nil? || transcript_path.empty?

    @transcript_path = transcript_path
  end

  def extract
    puts header
    puts
    puts format_script
  end

  private

  attr_reader :transcript_path

  def data
    @data ||= JSON.parse(File.read(transcript_path))
  end

  def segments
    data["segments"] or raise "transcript JSON has no 'segments' key: #{transcript_path}"
  end

  def header
    "# Video: #{video_filename}\n# Duration: #{format_timestamp(total_duration)}"
  end

  def video_filename
    File.basename(data["video_path"].to_s)
  end

  def total_duration
    segments.last["end"].to_f
  end

  def format_script
    segments.filter_map { |s| format_segment(s) }.join("\n\n")
  end

  def format_segment(segment)
    text   = segment["text"].to_s.strip
    visual = segment["visual"].to_s.strip
    ts     = format_timestamp(segment["start"].to_f)

    lines = []
    lines << "[#{ts}] [VISUAL] #{visual}" unless visual.empty?
    lines << "[#{ts}] #{text}" unless text.empty?

    lines.empty? ? nil : lines.join("\n")
  end

  def format_timestamp(seconds)
    total = seconds.to_i
    "%02d:%02d" % [total / 60, total % 60]
  end
end

if __FILE__ == $PROGRAM_NAME
  transcript_path = ARGV[0]
  abort("usage: visual_script_extractor.rb <visual_transcript.json>") unless transcript_path
  VisualScriptExtractor.extract(transcript_path)
end
