#!/usr/bin/env ruby
# frozen_string_literal: true

# Build contact sheets for an explicit list of clips in a library. Drives the
# contact-sheet skill directly — no agent in the loop. Each clip gets a `_full`
# sheet; clips longer than 10 minutes also get per-segment sheets covering
# successive 10-minute slices.
#
# Single-threaded by design. The parent agent decides how many invocations to
# run in parallel based on machine headroom.
#
# Usage:
#   ruby build_contact_sheets.rb <library_name> <clip> [<clip> ...]
#
#   <library_name>  e.g. my-library
#   <clip>          clip filename including extension, e.g. P1055016.MP4

require 'fileutils'

require_relative '../contact-sheet/contact_sheet'
require_relative 'library'

class ContactSheetBuilder
  CHUNK_THRESHOLD_SECONDS = 600.0 # 10 minutes
  CHUNK_LENGTH_SECONDS = 600.0

  def self.build(library_name, clips:)
    new(library_name, clips: clips).build
  end

  def initialize(library_name, clips:)
    raise ArgumentError, 'clips must be a non-empty array' if !clips.is_a?(Array) || clips.empty?

    @library = Library.find(library_name)
    @requested_clips = clips.map(&:to_s)
    missing_ext = @requested_clips.reject { |c| File.extname(c).length > 1 }
    raise ArgumentError, "clip filenames must include an extension: #{missing_ext.join(', ')}" if missing_ext.any?
    @counters = { built: 0, skipped: 0, missing: 0 }
    @completed_filenames = []
  end

  def build
    FileUtils.mkdir_p(File.join(@library.dir, 'contact_sheets'))
    videos = resolve_videos

    videos.each_with_index do |video, idx|
      result = process(video, idx + 1, videos.size)
      @counters[result] += 1 if @counters.key?(result)
      @completed_filenames << File.basename(video['path'].to_s) if %i[built skipped].include?(result)
    end

    @library.complete_contact_sheet!(@completed_filenames) unless @completed_filenames.empty?

    log ''
    log "Done. Built sheets for #{@counters[:built]} clip#{'s' unless @counters[:built] == 1}, skipped #{@counters[:skipped]} (already present)."
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
    path = video['path']
    prefix = "[#{index}/#{total}]"
    unless path && File.exist?(path)
      log "#{prefix} skip (missing file): #{path.inspect}", io: $stderr
      return :missing
    end

    clipname = File.basename(path, '.*')
    full_path = @library.artifact_path('contact_sheet', clipname)

    if File.exist?(full_path)
      log "#{prefix} skip #{clipname} (sheet already exists)"
      return :skipped
    end

    duration = parse_duration(video['duration'])
    log "#{prefix} build #{clipname} (#{video['duration']})"

    ContactSheet.extract(path, library_dir: @library.dir)
    build_chunks(path, clipname, duration) if duration > CHUNK_THRESHOLD_SECONDS
    log "#{prefix} done #{clipname}"

    :built
  end

  def build_chunks(video_path, clipname, duration)
    chunk_ranges(duration).each do |range_start, range_end|
      descriptor = "#{format_hms(range_start).tr(':', '-')}_to_#{format_hms(range_end).tr(':', '-')}"
      chunk_path = File.join(@library.dir, 'contact_sheets', "#{clipname}_#{descriptor}.jpg")
      next if File.exist?(chunk_path)

      log "  + chunk #{format_hms(range_start)}–#{format_hms(range_end)}"
      ContactSheet.extract(video_path, range_start, range_end, library_dir: @library.dir)
    end
  end

  def log(line, io: $stdout)
    io.puts(line)
  end

  def chunk_ranges(duration)
    ranges = []
    start = 0.0
    while start < duration
      stop = [start + CHUNK_LENGTH_SECONDS, duration].min
      ranges << [start, stop]
      start = stop
    end
    ranges
  end

  # Accepts "HH:MM:SS" / "MM:SS" / a numeric seconds value. Anything else
  # raises — better to fail loudly than silently mis-chunk.
  def parse_duration(value)
    return value.to_f if value.is_a?(Numeric)

    str = value.to_s.strip
    raise ArgumentError, "video missing duration: #{value.inspect}" if str.empty?

    parts = str.split(':').map(&:to_f)
    case parts.length
    when 3 then parts[0] * 3600 + parts[1] * 60 + parts[2]
    when 2 then parts[0] * 60 + parts[1]
    when 1 then parts[0]
    else raise ArgumentError, "unrecognized duration format: #{value.inspect}"
    end
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
    warn 'Usage: ruby build_contact_sheets.rb <library_name> <clip> [<clip> ...]'
    exit 1
  end

  begin
    ContactSheetBuilder.build(library_name, clips: clips)
  rescue StandardError => e
    warn "build_contact_sheets: #{e.message}"
    exit 1
  end
end
