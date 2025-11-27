#!/usr/bin/env ruby
# Benchmark: Fixed-interval frame extraction vs FFmpeg scene detection
#
# Usage: ruby benchmark/frame_detection_benchmark.rb [video_path]
#        If no video_path provided, uses spec/fixtures/media/*.mov
#
# Compares two approaches:
# 1. Current: Fixed interval sampling (start/middle/end, then subdivide)
# 2. Proposed: FFmpeg scene detection with select='gt(scene,THRESHOLD)'

require 'open3'
require 'json'
require 'fileutils'

class FrameDetectionBenchmark
  TEMP_DIR = '/tmp/benchmark_frames'

  # Scene detection thresholds from issue #8
  THRESHOLDS = {
    interviews: 0.5,
    action: 0.25,
    broll: 0.4,
    presentations: 0.6
  }

  def initialize(video_paths)
    @video_paths = video_paths
    @results = []
  end

  def run
    puts "=" * 60
    puts "Frame Detection Benchmark"
    puts "=" * 60

    @video_paths.each do |video_path|
      benchmark_video(video_path)
    end

    print_summary
    @results
  end

  private

  def benchmark_video(video_path)
    puts "\n📹 Benchmarking: #{File.basename(video_path)}"
    puts "-" * 50

    duration = get_duration(video_path)
    puts "   Duration: #{duration.round(2)}s"

    result = {
      video: File.basename(video_path),
      duration: duration,
      methods: {}
    }

    # Method 1: Current fixed-interval approach
    fixed_result = benchmark_fixed_interval(video_path, duration)
    result[:methods][:fixed_interval] = fixed_result

    # Method 2: Scene detection with various thresholds
    THRESHOLDS.each do |content_type, threshold|
      scene_result = benchmark_scene_detection(video_path, threshold, content_type)
      result[:methods][:"scene_#{content_type}"] = scene_result
    end

    @results << result
  end

  def benchmark_fixed_interval(video_path, duration)
    puts "\n   [1] Fixed Interval (current approach)"

    output_dir = "#{TEMP_DIR}/fixed"
    FileUtils.mkdir_p(output_dir)

    # Calculate timestamps based on current SKILL.md logic
    timestamps = if duration <= 30
      [2.0]  # Single frame at 2s for short videos
    else
      [2.0, duration / 2.0, duration - 2.0]  # Start, middle, end
    end

    start_time = Time.now

    timestamps.each_with_index do |ts, idx|
      ts_formatted = format_timestamp(ts)
      cmd = [
        'ffmpeg', '-y', '-ss', ts_formatted,
        '-i', video_path,
        '-vframes', '1',
        '-vf', 'scale=1280:-1',
        "#{output_dir}/frame_#{idx}.jpg"
      ]

      stdout, stderr, status = Open3.capture3(*cmd)
      unless status.success?
        puts "       ⚠️  Warning: Failed to extract frame at #{ts_formatted}"
      end
    end

    elapsed = Time.now - start_time
    frame_count = Dir["#{output_dir}/*.jpg"].count

    puts "       Frames extracted: #{frame_count}"
    puts "       Time elapsed: #{(elapsed * 1000).round(1)}ms"

    FileUtils.rm_rf(output_dir)

    {
      frames: frame_count,
      time_ms: (elapsed * 1000).round(1),
      timestamps: timestamps
    }
  end

  def benchmark_scene_detection(video_path, threshold, content_type)
    puts "\n   [2] Scene Detection (#{content_type}, threshold=#{threshold})"

    output_dir = "#{TEMP_DIR}/scene_#{content_type}"
    FileUtils.mkdir_p(output_dir)

    start_time = Time.now

    # Method A: Extract scene change frames directly
    cmd = [
      'ffmpeg', '-y',
      '-i', video_path,
      '-vf', "select='gt(scene,#{threshold})',scale=1280:-1",
      '-vsync', 'vfr',
      "#{output_dir}/scene_%04d.jpg"
    ]

    stdout, stderr, status = Open3.capture3(*cmd)

    elapsed_extract = Time.now - start_time
    frame_count = Dir["#{output_dir}/*.jpg"].count

    # Also measure just the detection time (no frame output)
    start_time = Time.now
    detect_cmd = [
      'ffmpeg',
      '-i', video_path,
      '-vf', "select='gt(scene,#{threshold})',showinfo",
      '-f', 'null', '-'
    ]

    stdout, stderr, status = Open3.capture3(*detect_cmd)
    elapsed_detect = Time.now - start_time

    # Parse detected timestamps from stderr
    timestamps = stderr.scan(/pts_time:([\d.]+)/).flatten.map(&:to_f)

    puts "       Frames extracted: #{frame_count}"
    puts "       Scene changes detected: #{timestamps.count}"
    puts "       Detection only: #{(elapsed_detect * 1000).round(1)}ms"
    puts "       Extract + save: #{(elapsed_extract * 1000).round(1)}ms"

    if timestamps.any?
      puts "       Timestamps: #{timestamps.map { |t| "#{t.round(2)}s" }.join(', ')}"
    end

    FileUtils.rm_rf(output_dir)

    {
      frames: frame_count,
      detected_scenes: timestamps.count,
      detection_time_ms: (elapsed_detect * 1000).round(1),
      extract_time_ms: (elapsed_extract * 1000).round(1),
      timestamps: timestamps
    }
  end

  def get_duration(video_path)
    cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', video_path]
    stdout, stderr, status = Open3.capture3(*cmd)

    raise "ffprobe failed: #{stderr}" unless status.success?

    data = JSON.parse(stdout)
    data['format']['duration'].to_f
  end

  def format_timestamp(seconds)
    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    secs = seconds % 60
    format('%02d:%02d:%06.3f', hours, minutes, secs)
  end

  def print_summary
    puts "\n" + "=" * 60
    puts "SUMMARY"
    puts "=" * 60

    @results.each do |result|
      puts "\n#{result[:video]} (#{result[:duration].round(2)}s):"

      fixed = result[:methods][:fixed_interval]
      puts "  Fixed interval: #{fixed[:frames]} frames in #{fixed[:time_ms]}ms"

      result[:methods].each do |method, data|
        next if method == :fixed_interval
        content_type = method.to_s.sub('scene_', '')
        puts "  Scene (#{content_type}): #{data[:detected_scenes]} scenes detected in #{data[:detection_time_ms]}ms"
      end
    end

    puts "\n" + "-" * 60
    puts "RECOMMENDATIONS (from issue #8):"
    puts "  - Interviews/talking heads: threshold 0.4-0.6 (default 0.5)"
    puts "  - Action/sports: threshold 0.2-0.3 (default 0.25)"
    puts "  - B-roll: threshold 0.3-0.5 (default 0.4)"
    puts "  - Presentations/static: threshold 0.5-0.7 (default 0.6)"
    puts "-" * 60
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    # Use test fixtures
    fixtures_dir = File.expand_path('../spec/fixtures/media', __dir__)
    video_paths = Dir["#{fixtures_dir}/*.mov"]

    if video_paths.empty?
      puts "No video files found. Usage: ruby #{$PROGRAM_NAME} video1.mov [video2.mov ...]"
      exit 1
    end
  else
    video_paths = ARGV.map { |p| File.expand_path(p) }

    missing = video_paths.reject { |p| File.exist?(p) }
    if missing.any?
      puts "Error: Files not found: #{missing.join(', ')}"
      exit 1
    end
  end

  # Check ffmpeg is available
  unless system('which ffmpeg > /dev/null 2>&1')
    puts "Error: ffmpeg not found. Please install ffmpeg first."
    exit 1
  end

  FileUtils.mkdir_p(FrameDetectionBenchmark::TEMP_DIR)

  begin
    benchmark = FrameDetectionBenchmark.new(video_paths)
    benchmark.run
  ensure
    FileUtils.rm_rf(FrameDetectionBenchmark::TEMP_DIR)
  end
end
