#!/usr/bin/env ruby
require 'fileutils'

# Builds timestamped grid montage(s) for a video.
# For clips ≤10 minutes, produces a single adaptive grid. For longer clips,
# produces one adaptive grid per 10-minute chunk (ceiling division), so a
# 25-minute clip gets three grids. Each grid covers its own window with
# evenly spaced tiles labeled HH:MM:SS in absolute video time.
#
# Extracts each tile with its own short-lived ffmpeg invocation (input-level
# seek + software decode) and composes the final grid with ImageMagick
# `magick montage`. A single ffmpeg with N parallel inputs peaks at multiple
# GB of RSS on Apple Silicon; sequential single-input invocations stay under
# ~600 MB peak with only a ~20% wall-time penalty.
#
# We don't enable `-hwaccel videotoolbox` because it silently fails on common
# pixel formats VideoToolbox can't decode (notably the 10-bit 4:2:2 H.264 the
# Panasonic Lumix records to .mov) — ffmpeg returns success but produces no
# tile. Software decode handles every codec in a uniform path.

class GridMontage
  DEFAULT_FIXED_GRID = 4
  DEFAULT_TILE_W = 392
  DEFAULT_TILE_H = 220
  FONT = "/System/Library/Fonts/Helvetica.ttc"
  CHUNK_DURATION = 600  # 10 minutes
  Layout = Struct.new(:columns, :rows) do
    def tiles
      columns * rows
    end

    def montage_tile
      "#{columns}x#{rows}"
    end
  end
  ADAPTIVE_LAYOUTS = [
    [5, Layout.new(3, 1)],
    [10, Layout.new(2, 2)],
    [30, Layout.new(3, 2)],
    [60, Layout.new(4, 2)],
    [120, Layout.new(4, 3)],
    [Float::INFINITY, Layout.new(4, 4)],
  ].freeze

  def self.build(video_path:, output_path:, grid: nil,
                 tile_w: DEFAULT_TILE_W, tile_h: DEFAULT_TILE_H)
    new(video_path: video_path, output_path: output_path,
        grid: grid, tile_w: tile_w, tile_h: tile_h).build
  end

  def self.layout_for_duration(duration)
    ADAPTIVE_LAYOUTS.find { |max_duration, _| duration <= max_duration }.last
  end

  def initialize(video_path:, output_path:, grid:, tile_w:, tile_h:)
    raise ArgumentError, "video_path required" if video_path.nil? || video_path.empty?
    raise ArgumentError, "output_path required" if output_path.nil? || output_path.empty?
    raise ArgumentError, "grid must be positive" if grid && grid <= 0
    @video_path = video_path
    @output_path = output_path
    @fixed_grid = grid
    @tile_w = tile_w
    @tile_h = tile_h
  end

  def build
    @duration = probe_duration
    FileUtils.mkdir_p(File.dirname(@output_path))
    chunks = compute_chunks
    chunks.each_with_index.map do |(start_t, end_t), i|
      out = chunk_output_path(i, chunks.size)
      build_chunk(start_t, end_t, out)
      out
    end
  end

  private

  def compute_chunks
    num_chunks = (@duration / CHUNK_DURATION.to_f).ceil
    num_chunks.times.map do |i|
      start_t = i * CHUNK_DURATION
      end_t = [(i + 1) * CHUNK_DURATION, @duration].min
      [start_t, end_t]
    end
  end

  def chunk_output_path(index, total)
    return @output_path if total == 1
    dir = File.dirname(@output_path)
    ext = File.extname(@output_path)
    base = File.basename(@output_path, ext)
    File.join(dir, "#{base}_#{index + 1}#{ext}")
  end

  def build_chunk(start_t, end_t, output)
    layout = layout_for(start_t, end_t)
    tile_paths = []
    compute_seek_times(start_t, end_t, layout.tiles).each_with_index do |t, i|
      tile_paths << extract_tile(t, i, output)
    end
    compose_grid(tile_paths, output, layout)
  ensure
    tile_paths&.each { |p| File.unlink(p) if File.exist?(p) }
  end

  def layout_for(start_t, end_t)
    return Layout.new(@fixed_grid, @fixed_grid) if @fixed_grid

    self.class.layout_for_duration(end_t - start_t)
  end

  def extract_tile(time, index, output)
    tile_path = tile_path_for(output, index)
    cmd = [
      "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
      "-ss", time.to_s,
      "-i", @video_path,
      "-vf", tile_filter(time),
      "-frames:v", "1",
      "-pix_fmt", "yuvj420p",
      tile_path,
    ]
    success = system(*cmd)
    raise "ffmpeg failed extracting tile #{index} (t=#{time}) for #{@video_path}" unless success
    raise "ffmpeg returned success but produced no tile: #{tile_path}" unless File.exist?(tile_path)
    tile_path
  end

  def tile_filter(time)
    "scale=#{@tile_w}:#{@tile_h}:force_original_aspect_ratio=decrease," \
      "pad=#{@tile_w}:#{@tile_h}:(ow-iw)/2:(oh-ih)/2," \
      "drawtext=fontfile=#{FONT}:text='#{label_for(time)}':fontsize=22:fontcolor=white:" \
      "box=1:boxcolor=black@0.75:boxborderw=4:x=8:y=8"
  end

  def label_for(time)
    hours = (time / 3600).to_i
    mins = ((time % 3600) / 60).to_i
    secs = (time % 60).to_i
    format("%02d\\:%02d\\:%02d", hours, mins, secs)
  end

  def tile_path_for(output, index)
    dir = File.dirname(output)
    base = File.basename(output, File.extname(output))
    File.join(dir, "#{base}_tile_#{format("%02d", index)}.jpg")
  end

  def compose_grid(tile_paths, output, layout)
    cmd = ["magick", "montage", *tile_paths,
           "-tile", layout.montage_tile, "-geometry", "+0+0", output]
    return if system(*cmd)
    fallback = ["montage", *tile_paths,
                "-tile", layout.montage_tile, "-geometry", "+0+0", output]
    raise "magick/montage failed composing grid for #{@video_path}" unless system(*fallback)
  end

  # Clamp the last tile to (end_t - SEEK_SAFETY) so ffmpeg doesn't seek past the
  # last decodable frame on very short clips. A 1.25s .mov failed every retry
  # at seek≥1.18s; 0.5s of headroom keeps us inside the last keyframe window
  # without losing meaningful coverage on longer clips. When the duration is
  # too short to honor the headroom, the trailing tiles collapse to the same
  # frame — a degenerate grid, but it succeeds.
  SEEK_SAFETY = 0.5

  def compute_seek_times(start_t, end_t, tile_count)
    step = (end_t - start_t) / tile_count.to_f
    safe_max = [end_t - SEEK_SAFETY, start_t].max
    (0...tile_count).map do |i|
      target = start_t + i * step + step / 2.0
      [target, safe_max].min.round(2)
    end
  end

  def probe_duration
    out = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{shell_escape(@video_path)}`
    raise "ffprobe failed reading duration of #{@video_path}" unless $?.success?
    duration = out.strip.to_f
    raise "ffprobe returned non-positive duration for #{@video_path}: #{out.inspect}" unless duration.positive?
    duration
  end

  def shell_escape(str)
    "'#{str.gsub("'", "'\\''")}'"
  end

end

if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 2
    warn "usage: grid_montage.rb <video_path> <output_path> [fixed_grid_size]"
    exit 1
  end
  paths = GridMontage.build(
    video_path: ARGV[0],
    output_path: ARGV[1],
    grid: (ARGV[2].to_i if ARGV[2]),
  )
  paths.each { |p| puts "wrote #{p}" }
end
