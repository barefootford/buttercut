#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'json'
require 'yaml'

class FullTranscript
  def self.export(library_name, project_root = Dir.pwd)
    new(library_name, project_root).export
  end

  def initialize(library_name, project_root = Dir.pwd)
    raise ArgumentError, "library_name is required" if library_name.nil? || library_name.strip.empty?

    @project_root = project_root
    @library_dir = File.join(project_root, 'libraries', library_name)
    @transcripts_dir = File.join(@library_dir, 'transcripts')
    @summaries_dir = File.join(@library_dir, 'summaries')
    @output_path = File.join(@library_dir, 'full_transcript.txt')
  end

  def export
    library = load_library
    # Images have no transcript key, so they fall into the skipped count
    # naturally — only spoken footage lands in the export.
    videos = library['media'] || []

    lines = []
    skipped = 0

    videos.each do |video|
      transcript_file = video['transcript']
      unless transcript_file && !transcript_file.empty?
        skipped += 1
        next
      end

      filename = File.basename(video['path'] || transcript_file)
      description = extract_overview(video['summary'])
      dialogue = extract_dialogue(transcript_file)

      lines << filename
      lines << "// summary: #{description}" if description
      lines << (dialogue.empty? ? "[no dialogue]" : dialogue)
      lines << ""
    end

    File.write(@output_path, lines.join("\n"))

    puts "✅ Full transcript written to #{@output_path}"
    puts "   #{videos.size - skipped} clips with transcripts, #{skipped} skipped (no transcript)"
    @output_path
  end

  private

  def load_library
    yaml_path = File.join(@library_dir, 'library.yaml')
    raise "Library not found: #{yaml_path}" unless File.exist?(yaml_path)

    YAML.load(File.read(yaml_path, encoding: 'UTF-8'), permitted_classes: [Date, Time, Symbol])
  end

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
