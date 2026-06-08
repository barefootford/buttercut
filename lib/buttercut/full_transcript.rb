#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'library'

class FullTranscript
  def self.export(library_name)
    new(library_name).export
  end

  def initialize(library_name)
    # Reading through Library (not raw YAML) inherits its normalization —
    # `media` is always an array, and a legacy `videos:` library fails loudly
    # with the "run migrate" error instead of producing an all-skipped file.
    @library = Library.find(library_name)
    @transcripts_dir = File.join(@library.dir, 'transcripts')
    @summaries_dir = File.join(@library.dir, 'summaries')
    @output_path = File.join(@library.dir, 'full_transcript.txt')
  end

  def export
    clips = @library.media

    lines = []
    skipped = 0

    clips.each do |clip|
      transcript_file = clip['transcript']
      # Stills (and any clip without a transcript) carry no dialogue — skip them.
      unless transcript_file && !transcript_file.empty?
        skipped += 1
        next
      end

      filename = File.basename(clip['path'] || transcript_file)
      description = extract_overview(clip['summary'])
      dialogue = extract_dialogue(transcript_file)

      lines << filename
      lines << "// summary: #{description}" if description
      lines << (dialogue.empty? ? "[no dialogue]" : dialogue)
      lines << ""
    end

    File.write(@output_path, lines.join("\n"))

    puts "✅ Full transcript written to #{@output_path}"
    puts "   #{clips.size - skipped} clips with transcripts, #{skipped} skipped (no transcript)"
    @output_path
  end

  private

  def extract_overview(summary_file)
    return nil unless summary_file && !summary_file.empty?

    path = File.join(@summaries_dir, summary_file)
    return nil unless File.exist?(path)

    content = File.read(path, encoding: 'utf-8')
    overview_match = content.match(/^## Overview\n+(.*?)(?:\n\n|\z)/m)
    return nil unless overview_match

    first_sentence = overview_match[1].split(/(?<=[.!?])\s+/).first
    first_sentence&.strip
  end

  def extract_dialogue(transcript_file)
    path = File.join(@transcripts_dir, transcript_file)
    return "" unless File.exist?(path)

    data = JSON.parse(File.read(path, encoding: 'UTF-8'))
    segments = data['segments'] || []
    segments.map { |s| s['text'].to_s.strip }.reject(&:empty?).join("\n")
  end
end

if __FILE__ == $PROGRAM_NAME
  library_name = ARGV[0]
  if library_name.nil? || library_name.empty?
    puts "Usage: ruby full_transcript.rb <library-name>"
    exit 1
  end

  begin
    FullTranscript.export(library_name)
  rescue => e
    puts "❌ #{e.message}"
    exit 1
  end
end
