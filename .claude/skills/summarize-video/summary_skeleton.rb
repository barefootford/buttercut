#!/usr/bin/env ruby
# Pre-create a summary skeleton file for the summarize-video skill,
# with header (filename, duration) filled in and four placeholder markers
# in the body for the sub-agent to replace via Edit.
#
# Usage:
#   ruby summary_skeleton.rb <visual_transcript.json> <summary_output.md>

require 'json'

class SummarySkeleton
  def self.create(transcript_path, output_path)
    new(transcript_path, output_path).create
  end

  def initialize(transcript_path, output_path)
    raise ArgumentError, "transcript_path is required" if transcript_path.nil? || transcript_path.empty?
    raise ArgumentError, "output_path is required" if output_path.nil? || output_path.empty?

    @transcript_path = transcript_path
    @output_path = output_path
  end

  def create
    File.write(output_path, skeleton)
    puts "skeleton: #{output_path}"
  end

  private

  attr_reader :transcript_path, :output_path

  def data
    @data ||= JSON.parse(File.read(transcript_path))
  end

  def video_filename
    File.basename(data["video_path"].to_s)
  end

  def segments
    data["segments"] or raise "transcript JSON has no 'segments' key: #{transcript_path}"
  end

  def total_duration
    segments.last["end"].to_f
  end

  def format_timestamp(seconds)
    total = seconds.to_i
    "%02d:%02d" % [total / 60, total % 60]
  end

  def skeleton
    <<~MD
      # #{video_filename}
      **Duration:** #{format_timestamp(total_duration)}

      ## Overview
      <!-- FILL_OVERVIEW -->

      ## Key Visuals
      <!-- FILL_KEY_VISUALS -->

      ## Notable Dialogue
      <!-- FILL_DIALOGUE -->

      ## B-Roll
      <!-- FILL_BROLL -->
    MD
  end
end

if __FILE__ == $PROGRAM_NAME
  transcript_path, output_path = ARGV
  abort("usage: summary_skeleton.rb <visual_transcript.json> <summary_output.md>") unless transcript_path && output_path
  SummarySkeleton.create(transcript_path, output_path)
end
