#!/usr/bin/env ruby
# frozen_string_literal: true

# Build clean dialogue scripts for every video in a library that doesn't
# already have one. Wraps ScriptExtractor over each clip's audio transcript.
# Deterministic, no LLM — same parent-side pre-bake pattern as
# build_contact_sheets.rb so sub-agents don't have to shell out per-clip.
#
# Usage:
#   ruby build_scripts.rb <library_name>

require 'fileutils'

require_relative 'script_extractor'
require_relative 'library'

class ScriptBuilder
  def self.build(library_name)
    new(library_name).build
  end

  def initialize(library_name)
    @library = Library.find(library_name)
  end

  def build
    FileUtils.mkdir_p(File.join(@library.dir, 'scripts'))
    counters = { built: 0, skipped: 0, missing: 0 }
    completed = []
    videos = @library.videos

    videos.each_with_index do |video, idx|
      result = process(video, idx + 1, videos.size)
      counters[result] += 1
      completed << File.basename(video['path'].to_s) if %i[built skipped].include?(result)
    end

    @library.complete_script!(completed) unless completed.empty?

    puts ''
    puts "Done. Built scripts for #{counters[:built]} clip#{'s' unless counters[:built] == 1}, " \
         "skipped #{counters[:skipped]} (already present)" \
         "#{counters[:missing].positive? ? ", #{counters[:missing]} missing transcript" : ''}."
  end

  private

  def process(video, index, total)
    prefix = "[#{index}/#{total}]"
    clipname = File.basename(video['path'].to_s, '.*')

    if blank?(video['transcript'])
      warn "#{prefix} skip #{clipname} (no transcript on file)"
      return :missing
    end

    transcript_path = @library.artifact_path('transcript', clipname)
    unless File.exist?(transcript_path)
      warn "#{prefix} skip #{clipname} (transcript file missing: #{transcript_path})"
      return :missing
    end

    script_path = @library.artifact_path('script', clipname)
    if File.exist?(script_path)
      puts "#{prefix} skip #{clipname} (script already exists)"
      return :skipped
    end

    ScriptExtractor.extract(transcript_path, script_path)
    :built
  end

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
end

if __FILE__ == $PROGRAM_NAME
  library_name = ARGV[0]
  if library_name.nil? || library_name.empty?
    warn 'Usage: ruby build_scripts.rb <library_name>'
    exit 1
  end

  begin
    ScriptBuilder.build(library_name)
  rescue StandardError => e
    warn "build_scripts: #{e.message}"
    exit 1
  end
end
