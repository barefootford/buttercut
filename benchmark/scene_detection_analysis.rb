#!/usr/bin/env ruby
# Analyze scene detection output for a video
#
# Usage: ruby benchmark/scene_detection_analysis.rb video.mov [threshold]
#
# This script runs FFmpeg scene detection and outputs:
# - All detected scene changes with timestamps
# - Frame count comparison between methods
# - Processing time breakdown

require 'open3'
require 'json'

def run_scene_detection(video_path, threshold = 0.4)
  puts "Analyzing: #{video_path}"
  puts "Threshold: #{threshold}"
  puts "-" * 50

  # Get video duration
  probe_cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', video_path]
  stdout, _, status = Open3.capture3(*probe_cmd)
  raise "ffprobe failed" unless status.success?

  duration = JSON.parse(stdout)['format']['duration'].to_f
  puts "Duration: #{duration.round(2)}s"

  # Run scene detection with showinfo to get timestamps
  puts "\nRunning scene detection..."
  start_time = Time.now

  cmd = [
    'ffmpeg', '-i', video_path,
    '-vf', "select='gt(scene,#{threshold})',showinfo",
    '-f', 'null', '-'
  ]

  _, stderr, _ = Open3.capture3(*cmd)
  elapsed = Time.now - start_time

  # Parse scene timestamps from showinfo output
  # Format: [Parsed_showinfo_1 ...] n:123 pts:12345 pts_time:1.234
  scenes = stderr.scan(/pts_time:([\d.]+)/).flatten.map(&:to_f)

  puts "Detection time: #{(elapsed * 1000).round(1)}ms"
  puts "Scenes detected: #{scenes.count}"

  if scenes.any?
    puts "\nScene change timestamps:"
    scenes.each_with_index do |ts, i|
      puts "  #{i + 1}. #{format_time(ts)} (#{ts.round(3)}s)"
    end

    # Calculate intervals between scenes
    if scenes.count > 1
      puts "\nIntervals between scenes:"
      scenes.each_cons(2).with_index do |(a, b), i|
        interval = b - a
        puts "  #{i + 1}→#{i + 2}: #{interval.round(2)}s"
      end
    end
  else
    puts "\nNo scene changes detected at threshold #{threshold}"
    puts "Try a lower threshold (e.g., 0.2 or 0.3)"
  end

  # Compare with fixed interval approach
  puts "\n" + "=" * 50
  puts "COMPARISON: Fixed Interval vs Scene Detection"
  puts "=" * 50

  fixed_frames = if duration <= 30
    1
  else
    3  # start, middle, end
  end

  puts "\nFixed interval (current):"
  puts "  Frames: #{fixed_frames}"
  puts "  May require manual subdivision based on content"

  puts "\nScene detection (proposed):"
  puts "  Scenes detected: #{scenes.count}"
  puts "  Automatic, content-aware"

  if scenes.count > fixed_frames
    puts "\n✓ Scene detection found #{scenes.count - fixed_frames} more transition points"
  elsif scenes.count < fixed_frames && scenes.count > 0
    puts "\n✓ Scene detection is more efficient (fewer redundant frames)"
  elsif scenes.count == 0
    puts "\n⚠ No scenes detected - video may be static or threshold too high"
  end

  # Threshold recommendations
  puts "\n" + "-" * 50
  puts "THRESHOLD TUNING GUIDE:"
  puts "-" * 50
  puts "Current: #{threshold}"
  puts ""
  puts "Recommended by content type:"
  puts "  0.2-0.3  Action, sports, fast cuts"
  puts "  0.3-0.4  General purpose, B-roll"
  puts "  0.4-0.5  Talking heads, interviews"
  puts "  0.5-0.7  Presentations, static content"
  puts ""
  puts "Lower threshold = more scenes detected"
  puts "Higher threshold = fewer, more significant changes"
end

def format_time(seconds)
  mins = (seconds / 60).to_i
  secs = seconds % 60
  format('%02d:%05.2f', mins, secs)
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts "Usage: ruby #{$PROGRAM_NAME} video.mov [threshold]"
    puts "       threshold defaults to 0.4"
    exit 1
  end

  video_path = File.expand_path(ARGV[0])
  threshold = (ARGV[1] || 0.4).to_f

  unless File.exist?(video_path)
    puts "Error: File not found: #{video_path}"
    exit 1
  end

  unless system('which ffmpeg > /dev/null 2>&1')
    puts "Error: ffmpeg not found"
    exit 1
  end

  run_scene_detection(video_path, threshold)
end
