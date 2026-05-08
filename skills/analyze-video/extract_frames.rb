#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'fileutils'

class FrameExtractor
  SCENE_THRESHOLD = 0.05
  MIN_GAP_SECONDS = 2.0
  EDGE_PAD = 0.5
  MIN_FRAMES = 3

  def self.extract(video_path:, output_dir:)
    new(video_path: video_path, output_dir: output_dir).extract
  end

  def initialize(video_path:, output_dir:)
    raise ArgumentError, "video_path is required" if video_path.nil? || video_path.empty?
    raise ArgumentError, "output_dir is required" if output_dir.nil? || output_dir.empty?
    raise ArgumentError, "video not found: #{video_path}" unless File.exist?(video_path)

    @video_path = video_path
    @output_dir = output_dir
  end

  def extract
    duration = video_duration
    timestamps = build_timestamps(duration)
    FileUtils.mkdir_p(@output_dir)
    frames = timestamps.map { |t| extract_one(t) }
    report(duration, timestamps, frames)
  end

  private

  def video_duration
    out, _err, status = Open3.capture3(
      "ffprobe", "-v", "error", "-show_entries", "format=duration",
      "-of", "default=nw=1:nk=1", @video_path
    )
    raise "ffprobe failed for #{@video_path}" unless status.success?
    out.strip.to_f
  end

  def scene_change_timestamps
    cmd = [
      "ffmpeg", "-i", @video_path,
      "-vf", "select='gt(scene,#{SCENE_THRESHOLD})',showinfo",
      "-vsync", "vfr", "-f", "null", "-"
    ]
    _out, err, _status = Open3.capture3(*cmd)
    err.scan(/pts_time:([0-9.]+)/).flatten.map(&:to_f)
  end

  def build_timestamps(duration)
    raw = [EDGE_PAD] + scene_change_timestamps + [duration - EDGE_PAD]
    raw = raw.select { |t| t >= 0 && t <= duration }.sort
    deduped = dedupe(raw)
    deduped = pad_to_minimum(deduped, duration)
    deduped.map { |t| t.round(3) }
  end

  def dedupe(timestamps)
    kept = []
    timestamps.each do |t|
      kept << t if kept.empty? || (t - kept.last) >= MIN_GAP_SECONDS
    end
    kept
  end

  def pad_to_minimum(timestamps, duration)
    return timestamps if timestamps.size >= MIN_FRAMES
    fills = (1..MIN_FRAMES).map { |i| (duration * i / (MIN_FRAMES + 1)).round(3) }
    result = dedupe((timestamps + fills).sort)
    return result if result.size >= MIN_FRAMES

    # Floor guarantee: dedupe was too aggressive (e.g. clustered scene changes
    # blocking evenly-spaced fills). Split the largest gaps until the floor holds.
    bounds = [0.0] + result + [duration]
    (MIN_FRAMES - result.size).times do
      largest = (0...bounds.size - 1).max_by { |i| bounds[i + 1] - bounds[i] }
      midpoint = ((bounds[largest] + bounds[largest + 1]) / 2.0).round(3)
      bounds.insert(largest + 1, midpoint)
    end
    bounds[1...-1]
  end

  def extract_one(timestamp)
    label = format("%07.3f", timestamp).sub(".", "p")
    path = File.join(@output_dir, "frame_#{label}.jpg")
    cmd = [
      "ffmpeg", "-y", "-ss", timestamp.to_s, "-i", @video_path,
      "-vframes", "1", "-vf", "scale=1280:-1", path
    ]
    _out, _err, status = Open3.capture3(*cmd)
    raise "ffmpeg extract failed at t=#{timestamp}" unless status.success?
    { time: timestamp, path: path }
  end

  def report(duration, timestamps, frames)
    JSON.pretty_generate(
      "video" => @video_path,
      "duration" => duration.round(3),
      "sampled_timestamps" => timestamps,
      "frames" => frames.map { |f| { "time" => f[:time], "path" => f[:path] } }
    )
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.size != 2
    abort "Usage: ruby extract_frames.rb <video_path> <output_dir>"
  end
  puts FrameExtractor.extract(video_path: ARGV[0], output_dir: ARGV[1])
end
