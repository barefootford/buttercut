#!/usr/bin/env ruby
# frozen_string_literal: true

# Build contact sheets for ONE clip: a `_full` sheet covering the whole clip,
# plus a per-segment sheet for each successive 10-minute slice of clips longer
# than 10 minutes. Pure ffmpeg via ContactSheet — no LLM, no library.yaml writes.
#
# This is the per-clip job. Orchestration — which clips, how many at once,
# recording completion — lives in JobRunner, driven by process_footage.rb's
# contact-sheets step.

require_relative 'job'
require_relative 'contact_sheet'

class ContactSheetJob < Job
  def self.field = 'contact_sheet'

  CHUNK_LENGTH_SECONDS = 600.0

  def initialize(library_name:, clip:, video_path:, duration:, library_dir:)
    super(library_name: library_name, clip: clip)
    @video_path = video_path
    @duration = duration
    @library_dir = library_dir
  end

  def perform
    raise "video file missing on disk: #{@video_path.inspect}" unless File.exist?(@video_path.to_s)

    ContactSheet.extract(@video_path, library_dir: @library_dir)
    chunk_ranges(ContactSheet.parse_hms(@duration)).each do |range_start, range_end|
      ContactSheet.extract(@video_path, range_start, range_end, library_dir: @library_dir)
    end
    self
  end

  private

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
end
