#!/usr/bin/env ruby
# frozen_string_literal: true

# Build contact sheets for every video in a library that doesn't already have
# one. Drives the contact-sheet skill directly — no agent in the loop. Each
# video gets a `_full` sheet; clips longer than 10 minutes also get
# per-segment sheets covering successive 10-minute slices.
#
# Usage:
#   ruby build_contact_sheets.rb <library_name> [--limit N | --all]
#
#   <library_name>  e.g. my-library
#   --limit N       stop after generating sheets for N clips
#   --all           process every remaining clip (no batch cap)
#
# Defaults to a batch of 10 clips per invocation. Re-run until the script
# reports nothing was built. Batching keeps long libraries interruptible and
# gives the caller a chance to spot-check sheets before committing the rest.

require 'optparse'
require 'fileutils'

require_relative '../contact-sheet/contact_sheet'
require_relative 'library'

class ContactSheetBuilder
  CHUNK_THRESHOLD_SECONDS = 600.0 # 10 minutes
  CHUNK_LENGTH_SECONDS = 600.0
  DEFAULT_LIMIT = 10
  # Empirical sweet spot on an M1: above 4 concurrent ffmpegs, videotoolbox
  # serializes GPU access and wall time gets worse. CPU stays in the 60-80%
  # band at P=4 — fast without taking over the machine.
  WORKERS = 4

  def self.build(library_name, limit: DEFAULT_LIMIT)
    new(library_name, limit: limit).build
  end

  def initialize(library_name, limit:)
    raise ArgumentError, 'limit must be a positive integer or nil' if limit && limit.to_i < 1

    @library = Library.find(library_name)
    @limit = limit&.to_i
    @log_mutex = Mutex.new
    @counters = { built: 0, skipped: 0, missing: 0 }
    @counters_mutex = Mutex.new
    @completed_filenames = []
    @completed_mutex = Mutex.new
  end

  def build
    FileUtils.mkdir_p(File.join(@library.dir, 'contact_sheets'))
    videos = @library.videos
    queue = build_queue(videos)

    workers = WORKERS.times.map do
      Thread.new do
        while (item = queue.pop(true) rescue nil)
          video, index = item
          result = process(video, index, videos.size)
          @counters_mutex.synchronize { @counters[result] += 1 if @counters.key?(result) }
          if %i[built skipped].include?(result)
            @completed_mutex.synchronize { @completed_filenames << File.basename(video['path'].to_s) }
          end
        end
      end
    end
    workers.each(&:join)

    @library.complete_contact_sheet!(@completed_filenames) unless @completed_filenames.empty?

    log ''
    log "Done. Built sheets for #{@counters[:built]} clip#{'s' unless @counters[:built] == 1}, skipped #{@counters[:skipped]} (already present)."
  end

  # Sort by descending duration so the slowest clips start first — short clips
  # backfill while the long ones decode, instead of becoming a tail at the end.
  def build_queue(videos)
    queue = Queue.new
    enqueued = 0
    videos
      .each_with_index
      .sort_by { |video, _idx| -parse_duration_safely(video['duration']) }
      .each do |video, idx|
        break if @limit && enqueued >= @limit
        queue << [video, idx + 1]
        enqueued += 1
      end
    queue
  end

  def parse_duration_safely(value)
    parse_duration(value)
  rescue StandardError
    0.0
  end

  private

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

  # Serialize stdout/stderr across worker threads so log lines don't interleave.
  def log(line, io: $stdout)
    @log_mutex.synchronize { io.puts(line) }
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
  options = { limit: ContactSheetBuilder::DEFAULT_LIMIT }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby build_contact_sheets.rb <library_name> [--limit N | --all]'
    opts.on('--limit N', Integer, "Stop after generating sheets for N clips (default #{ContactSheetBuilder::DEFAULT_LIMIT})") do |n|
      options[:limit] = n
    end
    opts.on('--all', 'Process every remaining clip (no batch cap)') do
      options[:limit] = nil
    end
  end
  parser.parse!

  library_name = ARGV[0]
  if library_name.nil? || library_name.empty?
    puts parser.help
    exit 1
  end

  begin
    ContactSheetBuilder.build(library_name, limit: options[:limit])
  rescue StandardError => e
    warn "build_contact_sheets: #{e.message}"
    exit 1
  end
end
