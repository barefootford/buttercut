#!/usr/bin/env ruby
# frozen_string_literal: true

# Build clean dialogue scripts for an explicit list of clips in a library.
# Wraps ScriptExtractor over each clip's audio transcript. Deterministic, no
# LLM — same parent-side pre-bake pattern as build_contact_sheets.rb so
# sub-agents don't have to shell out per-clip.
#
# Single-threaded by design. The parent agent decides how many invocations to
# run in parallel based on machine headroom.
#
# Usage:
#   ruby build_scripts.rb <library_name> <clip> [<clip> ...]
#
#   <library_name>  e.g. my-library
#   <clip>          clip filename including extension, e.g. P1055016.MP4

require 'fileutils'

require_relative 'script_extractor'
require_relative 'library'

class ScriptBuilder
  def self.build(library_name, clips:)
    new(library_name, clips: clips).build
  end

  def initialize(library_name, clips:)
    raise ArgumentError, 'clips must be a non-empty array' if !clips.is_a?(Array) || clips.empty?

    @library = Library.find(library_name)
    @requested_clips = clips.map(&:to_s)
    missing_ext = @requested_clips.reject { |c| File.extname(c).length > 1 }
    raise ArgumentError, "clip filenames must include an extension: #{missing_ext.join(', ')}" if missing_ext.any?
  end

  def build
    FileUtils.mkdir_p(File.join(@library.dir, 'scripts'))
    counters = { built: 0, skipped: 0, missing: 0 }
    completed = []
    videos = resolve_videos

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

  def resolve_videos
    by_filename = @library.videos.each_with_object({}) do |video, acc|
      acc[File.basename(video['path'].to_s)] = video
    end

    @requested_clips.map do |filename|
      video = by_filename[filename]
      raise ArgumentError, "clip not found in library: #{filename}" unless video

      video
    end
  end

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
  library_name = ARGV.shift
  clips = ARGV.dup

  if library_name.nil? || library_name.empty? || clips.empty?
    warn 'Usage: ruby build_scripts.rb <library_name> <clip> [<clip> ...]'
    exit 1
  end

  begin
    ScriptBuilder.build(library_name, clips: clips)
  rescue StandardError => e
    warn "build_scripts: #{e.message}"
    exit 1
  end
end
