#!/usr/bin/env ruby
# Generate thumbnail contact sheets from video files for AI scene detection.
# Outputs a grid of frames at configurable intervals for visual analysis.
#
# Usage:
#   ruby contact_sheet.rb <video> [--start S] [--end E] [--interval I] [--output PATH]

require 'json'
require 'optparse'

module ContactSheet
  THUMB_WIDTH = 240
  THUMB_HEIGHT = 135

  def self.interval_for_duration(duration_seconds)
    case duration_seconds
    when 0..60   then 5
    when 61..180 then 10
    when 181..300 then 15
    else              20
    end
  end

  def self.grid_dimensions(frame_count)
    cols = Math.sqrt(frame_count).ceil
    rows = (frame_count.to_f / cols).ceil
    [cols, rows]
  end

  def self.video_duration(video_path)
    cmd = "ffprobe -v quiet -print_format json -show_format #{video_path.shellescape}"
    output = `#{cmd}`
    data = JSON.parse(output)
    data['format']['duration'].to_f
  end

  def self.build_ffmpeg_command(video_path, output_path, interval:, cols:, rows:, start_time: nil, end_time: nil)
    args = ['ffmpeg', '-y']

    # Try GPU acceleration for HEVC
    args += ['-hwaccel', 'cuda'] if gpu_available?

    args += ['-ss', start_time.to_s] if start_time
    args += ['-i', video_path]
    args += ['-t', (end_time - start_time).to_s] if start_time && end_time

    vf = "fps=1/#{interval},scale=#{THUMB_WIDTH}:#{THUMB_HEIGHT},tile=#{cols}x#{rows}"
    args += ['-vf', vf, '-frames:v', '1', '-q:v', '3', output_path]
    args
  end

  def self.gpu_available?
    return @gpu_available unless @gpu_available.nil?
    @gpu_available = system('ffmpeg -hwaccels 2>/dev/null | grep -q cuda')
  end

  def self.generate(video_path, output_path:, interval: nil, start_time: nil, end_time: nil)
    require 'shellwords'

    duration = if start_time && end_time
                 end_time - start_time
               else
                 video_duration(video_path)
               end

    interval ||= interval_for_duration(duration)
    frame_count = (duration / interval).ceil
    frame_count = [frame_count, 1].max
    cols, rows = grid_dimensions(frame_count)

    cmd_args = build_ffmpeg_command(
      video_path, output_path,
      interval: interval, cols: cols, rows: rows,
      start_time: start_time, end_time: end_time
    )

    # Try with GPU, fall back to CPU on failure
    success = system(*cmd_args, [:out, :err] => '/dev/null')
    if !success && gpu_available?
      @gpu_available = false
      cmd_args = build_ffmpeg_command(
        video_path, output_path,
        interval: interval, cols: cols, rows: rows,
        start_time: start_time, end_time: end_time
      )
      success = system(*cmd_args, [:out, :err] => '/dev/null')
    end

    timestamps = (0...frame_count).map { |i| (start_time || 0) + (i * interval) }

    {
      output: output_path,
      frame_count: frame_count,
      grid: "#{cols}x#{rows}",
      interval: interval,
      timestamps: timestamps,
      success: success
    }
  end
end

# CLI entry point
if __FILE__ == $0
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} <video> [options]"
    opts.on('--start SECONDS', Float, 'Start time') { |v| options[:start_time] = v }
    opts.on('--end SECONDS', Float, 'End time') { |v| options[:end_time] = v }
    opts.on('--interval SECONDS', Float, 'Frame interval') { |v| options[:interval] = v }
    opts.on('--output PATH', 'Output JPG path') { |v| options[:output_path] = v }
  end.parse!

  video_path = ARGV[0]
  abort "Usage: #{$0} <video> [options]" unless video_path

  options[:output_path] ||= "/tmp/contact_sheet_#{File.basename(video_path, '.*')}.jpg"

  result = ContactSheet.generate(video_path, **options)
  puts result.to_json
end
