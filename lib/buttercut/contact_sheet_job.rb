#!/usr/bin/env ruby
# frozen_string_literal: true

# Build contact sheets for an explicit list of clips in a library. Drives the
# contact-sheet skill directly — no agent in the loop. Each clip gets a `_full`
# sheet; clips longer than 10 minutes also get per-segment sheets covering
# successive 10-minute slices. Existing sheets are overwritten.
#
# Single-threaded by design. The parent agent decides how many invocations to
# run in parallel based on machine headroom.
#
# Usage:
#   ruby contact_sheet_job.rb <library_name> <clip> [<clip> ...]
#
#   <library_name>  e.g. my-library
#   <clip>          clip filename including extension, e.g. P1055016.MP4

require 'fileutils'

require_relative 'contact_sheet'
require_relative 'library'

class ContactSheetJob
  CHUNK_LENGTH_SECONDS = 600.0

  def self.perform(library_name, clips:)
    new(library_name, clips: clips).perform
  end

  def initialize(library_name, clips:)
    raise ArgumentError, 'clips must be a non-empty array' if !clips.is_a?(Array) || clips.empty?

    clips = clips.map(&:to_s)
    missing_extension_clips = clips.select { |c| File.extname(c).length <= 1 }
    raise ArgumentError, "clip filenames must include an extension: #{missing_extension_clips.join(', ')}" if missing_extension_clips.any?

    @library = Library.find(library_name)
    @videos = resolve_videos(clips)
  end

  def perform
    FileUtils.mkdir_p(File.join(@library.dir, 'contact_sheets'))

    @videos.each_with_index do |video, idx|
      process_clip(video, idx + 1, @videos.size)
    end

    @library.complete!('contact_sheet', @videos.map { |v| File.basename(v['path']) })
    puts "\nDone. Built sheets for #{@videos.size} clip#{'s' unless @videos.size == 1}."
  end

  private

  def resolve_videos(requested)
    by_filename = @library.videos.each_with_object({}) do |video, acc|
      acc[File.basename(video['path'].to_s)] = video
    end

    requested.map do |filename|
      video = by_filename[filename]
      raise ArgumentError, "clip not found in library: #{filename}" unless video

      path = video['path']
      raise ArgumentError, "video file missing on disk: #{path.inspect}" unless File.exist?(path)

      video
    end
  end

  def process_clip(video, index, total)
    path = video['path']
    clipname = File.basename(path, '.*')
    duration = parse_duration(video['duration'])
    puts "[#{index}/#{total}] build #{clipname} (#{video['duration']})"

    ContactSheet.extract(path, library_dir: @library.dir)
    chunk_ranges(duration).each do |range_start, range_end|
      puts "  + chunk #{format_hms(range_start)}–#{format_hms(range_end)}"
      ContactSheet.extract(path, range_start, range_end, library_dir: @library.dir)
    end
  end

  def chunk_ranges(duration)
    return [] if duration <= CHUNK_LENGTH_SECONDS

    ranges = []
    start = 0.0
    while start < duration
      stop = [start + CHUNK_LENGTH_SECONDS, duration].min
      ranges << [start, stop]
      start = stop
    end
    ranges
  end

  def parse_duration(hms)
    h, m, s = hms.split(':').map(&:to_f)
    h * 3600 + m * 60 + s
  end

  def format_hms(seconds)
    total = seconds.to_i
    format('%02d:%02d:%02d', total / 3600, (total % 3600) / 60, total % 60)
  end
end

if __FILE__ == $PROGRAM_NAME
  library_name = ARGV.shift
  clips = ARGV.dup

  if library_name.nil? || library_name.empty? || clips.empty?
    warn 'Usage: ruby contact_sheet_job.rb <library_name> <clip> [<clip> ...]'
    exit 1
  end

  begin
    ContactSheetJob.perform(library_name, clips: clips)
  rescue StandardError => e
    warn "contact_sheet_job: #{e.message}"
    exit 1
  end
end
