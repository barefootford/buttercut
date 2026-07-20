#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'json'
require 'optparse'
require 'shellwords'
require_relative 'media_tools'
require_relative 'rotation_metadata'

class ContactSheet
  extend RotationMetadata

  DEFAULT_FRAMES = 16
  DEFAULT_COLS = 4
  SHORT_CLIP_THRESHOLD = 10.0
  SHORT_CLIP_FRAMES = 8
  SHORT_CLIP_COLS = 4
  # Portrait sources use a square grid (cols == rows) so the sheet inherits the footage's
  # orientation. The only case this actually changes is SHORT portrait clips: the default
  # short layout is 4x2, which with tall tiles comes out wider than tall (landscape). 3x3
  # fixes that. Long portrait clips were already portrait (4x4 of tall tiles is taller than
  # wide), so PORTRAIT_LONG_COLS == DEFAULT_COLS — it just makes the intent explicit.
  PORTRAIT_SHORT_COLS = 3
  PORTRAIT_LONG_COLS = 4
  GRID_WIDTH = 2500
  TILE_PADDING = 4
  TILE_MARGIN = 4
  FONT_PATH = File.expand_path('Arimo-Regular.ttf', __dir__)

  ALL_INTRA_CODECS = %w[prores dnxhd dnxhr mjpeg v210 rawvideo ffv1 huffyuv cfhd].freeze

  # Chroma subsamplings Apple Silicon videotoolbox won't decode (4:2:2, 4:4:4). Software
  # decode is slow per-frame, so the 16x decoder setup cost of seek-and-grab dominates and
  # single-pass wins on short ranges. 4:2:0 (incl. 10-bit yuv420p10le from HEVC drones /
  # iPhone) is fine — videotoolbox handles it.
  HEAVY_PIX_FMT_MARKERS = %w[422 444].freeze

  # Range length (seconds) below which a heavy clip prefers single-pass — decoding the whole
  # range once is cheaper than 16 heavy-decoder setups. Above this, seek-and-grab is the
  # lesser evil even though per-frame decode is slow.
  HEAVY_SINGLE_PASS_MAX_RANGE = 30.0

  # Single-pass assumes a constant frame rate so `fps=N/range` samples evenly. Variable
  # frame rate clips (screen captures, some action cams, AI-generated clips) violate that
  # assumption and produce bunched samples — kick those over to seek-and-grab.
  VFR_RATIO_THRESHOLD = 0.95

  attr_reader :codec, :pix_fmt, :rotation, :strategy, :hwaccel, :output_path

  def self.extract(video_path, start_time = nil, end_time = nil, library_dir: nil, output_path: nil)
    new(video_path, start_time, end_time, library_dir: library_dir, output_path: output_path).extract
  end

  def initialize(video_path, start_time, end_time, library_dir:, output_path:)
    raise ArgumentError, 'video_path is required' if video_path.nil? || video_path.strip.empty?
    raise ArgumentError, "video not found: #{video_path}" unless File.exist?(video_path)
    raise ArgumentError, "start_time must be >= 0 (got #{start_time})" if start_time && start_time.to_f.negative?
    raise ArgumentError, "library_dir not found: #{library_dir}" if library_dir && !File.directory?(library_dir)

    @video_path = File.expand_path(video_path)
    @start_time = start_time&.to_f
    @end_time = end_time&.to_f
    @whole_clip = start_time.nil? && end_time.nil?
    @library_dir = library_dir && File.expand_path(library_dir)
    @output_override = output_path
  end

  def extract
    probe
    @start_time ||= 0.0
    @end_time ||= @source_duration
    raise ArgumentError, "end_time #{format_hms(@end_time)} exceeds source duration #{format_hms(@source_duration)}" if @end_time > @source_duration + 0.5
    raise ArgumentError, "end_time must be > start_time (got #{@start_time}..#{@end_time})" if @end_time <= @start_time

    resolve_layout(@end_time - @start_time)
    @output_path = @output_override ? File.expand_path(@output_override) : default_output_path
    @strategy = pick_strategy
    @hwaccel = true

    run_with_fallback(sample_timestamps)
    report(@end_time - @start_time)
    @output_path
  end

  private

  def resolve_layout(range)
    short = range <= SHORT_CLIP_THRESHOLD
    if portrait?
      # Tiles from a vertical clip are taller than wide, so the usual 4-wide grid would
      # still come out wider than tall. A square grid (cols == rows) makes the sheet
      # itself portrait too, matching the footage.
      @cols = short ? PORTRAIT_SHORT_COLS : PORTRAIT_LONG_COLS
      @frames = @cols * @cols
    else
      @cols = short ? SHORT_CLIP_COLS : DEFAULT_COLS
      @frames = short ? SHORT_CLIP_FRAMES : DEFAULT_FRAMES
    end
    @rows = (@frames.to_f / @cols).ceil
    # Tile width chosen so the final grid is exactly GRID_WIDTH px wide after the tile
    # filter inserts (cols - 1) paddings between tiles and a margin on each side.
    @thumb_width = (GRID_WIDTH - (2 * TILE_MARGIN) - ((@cols - 1) * TILE_PADDING)) / @cols
  end

  # True when the clip displays taller than wide (after any container rotation) — either
  # natively portrait dimensions (no rotation tag) or landscape dimensions with a 90/270
  # rotation that rotation_filter applies. Drives the square portrait grid above.
  def portrait?
    return false unless @source_width.to_i.positive? && @source_height.to_i.positive?

    w, h = @source_width, @source_height
    w, h = h, w if [90, 270].include?(@rotation)
    h > w
  end

  # One ffprobe call returns duration (from format) plus everything dispatch needs:
  # codec/pix_fmt for #clip_class, frame-rate fields for VFR detection, and rotation
  # (legacy `tags.rotate` or modern displaymatrix side_data) for orientation correction.
  def probe
    cmd = "#{Shellwords.escape(MediaTools.ffprobe)} -v error -select_streams v:0 -show_format -show_streams -of json " \
          "#{Shellwords.escape(@video_path)}"
    data = JSON.parse(`#{cmd}`)
    stream = (data['streams'] || []).first || {}
    @source_duration = data.dig('format', 'duration').to_f
    raise "ffprobe failed for #{@video_path}" if @source_duration.zero?

    @codec = stream['codec_name'].to_s
    @pix_fmt = stream['pix_fmt'].to_s
    @source_width = stream['width'].to_i
    @source_height = stream['height'].to_i
    @rotation = self.class.extract_rotation(stream)
    @vfr = self.class.compute_vfr(stream['r_frame_rate'], stream['avg_frame_rate'])
  rescue JSON::ParserError
    raise "ffprobe failed for #{@video_path}"
  end

  # :all_intra → every frame is a keyframe; seek is essentially free.
  # :heavy     → 10/12-bit or 4:2:2/4:4:4; per-frame decode is expensive in software.
  # :light     → 8-bit 4:2:0 long-GOP (most consumer H.264 / HEVC). Default case.
  def clip_class
    return :all_intra if ALL_INTRA_CODECS.include?(@codec)
    return :heavy if heavy_pix_fmt?
    :light
  end

  def heavy_pix_fmt?
    HEAVY_PIX_FMT_MARKERS.any? { |marker| @pix_fmt.include?(marker) }
  end

  # Strategy selection. Seek-and-grab is the right default everywhere — it's bounded by
  # the number of frames sampled rather than the clip duration. The one exception is heavy
  # codecs on a short range, where the 16x decoder-setup cost outweighs decoding the whole
  # range once. VFR sources are always seek-and-grab — single-pass's `fps` filter assumes
  # constant frame rate and bunches samples otherwise.
  def pick_strategy
    return :seek_and_grab if @vfr
    return :single_pass if clip_class == :heavy && (@end_time - @start_time) <= HEAVY_SINGLE_PASS_MAX_RANGE

    :seek_and_grab
  end

  # `r_frame_rate` is what a CFR encoder would use; `avg_frame_rate` is total frames /
  # total duration. They diverge on VFR sources — screen recordings, some action cams,
  # AI-generated clips. Exposed as a class method so tests can pump raw rate strings
  # without spinning up ffmpeg.
  def self.compute_vfr(r_rate, a_rate)
    r = parse_rate(r_rate)
    a = parse_rate(a_rate)
    return false if r.nil? || a.nil? || r <= 0

    (a / r) < VFR_RATIO_THRESHOLD
  end

  def self.parse_rate(rate_str)
    num, den = rate_str.to_s.split('/').map(&:to_f)
    return nil if num.nil? || den.nil? || den.zero?

    num / den
  end

  # videotoolbox accelerates H.264/HEVC at 4:2:0 (any bit depth) on Apple Silicon — a real
  # 2-3x win on HEVC 10-bit drone clips. It refuses 4:2:2/4:4:4 chroma (Lumix High 4:2:2)
  # and we don't try to predict that; we just attempt with hwaccel and fall back on the
  # ffmpeg error.
  def run_with_fallback(timestamps)
    run_ffmpeg(args_for_strategy(timestamps))
  rescue RuntimeError => e
    raise unless @hwaccel

    warn "contact-sheet: hardware decode failed for #{File.basename(@video_path)}, retrying without videotoolbox"
    @hwaccel = false
    run_ffmpeg(args_for_strategy(timestamps))
  end

  def args_for_strategy(timestamps)
    case @strategy
    when :single_pass then single_pass_args(timestamps)
    when :seek_and_grab then seek_and_grab_args(timestamps)
    end
  end

  def default_output_path
    dir = output_dir
    base = File.basename(@video_path, '.*')
    File.join(dir, "#{base}_#{range_descriptor}.jpg")
  end

  def output_dir
    return File.dirname(@video_path) unless @library_dir

    File.join(@library_dir, 'contact_sheets')
  end

  def range_descriptor
    return 'full' if @whole_clip

    "#{format_hms(@start_time).tr(':', '-')}_to_#{format_hms(@end_time).tr(':', '-')}"
  end

  def sample_timestamps
    range = @end_time - @start_time
    (0...@frames).map { |i| @start_time + (i + 0.5) * range / @frames }
  end

  # Shared tail for both strategies: write exactly one JPEG with these encode
  # settings to the output path.
  def encode_output_args
    ['-fps_mode', 'vfr', '-pix_fmt', 'yuvj420p', '-q:v', '3', @output_path]
  end

  def single_pass_args(timestamps)
    range = @end_time - @start_time
    fps_value = @frames.to_f / range

    args = []
    args += ['-hwaccel', 'videotoolbox'] if @hwaccel
    args += ['-noautorotate']
    args += ['-ss', format('%.3f', @start_time)] if @start_time.positive?
    args += ['-to', format('%.3f', @end_time)] if @end_time < @source_duration - 0.5
    args += ['-i', @video_path, '-an', '-sn']
    args += ['-vf', single_pass_filter(timestamps, fps_value)]
    args += ['-frames:v', '1', *encode_output_args]
    args
  end

  def single_pass_filter(timestamps, fps_value)
    # `fps` resamples the decoded stream to exactly N frames over `range`. After this filter,
    # the frame counter `n` in drawtext runs 0, 1, 2, ..., N-1 — one drawtext per frame with
    # `enable='eq(n,i)'` paints the pre-computed timestamp for that tile.
    drawtext_chain = timestamps.each_with_index.map { |t, i| drawtext_filter(t, enable_index: i) }.join(',')

    [
      "fps=#{format('%.6f', fps_value)}",
      rotation_filter,
      "scale=#{@thumb_width}:-2:flags=lanczos",
      'setsar=1',
      drawtext_chain,
      "tile=#{@cols}x#{@rows}:padding=#{TILE_PADDING}:margin=#{TILE_MARGIN}:color=black"
    ].compact.join(',')
  end

  # Returns the transpose chain for the rotation we read from container metadata, or nil
  # if no rotation is needed. We use `-noautorotate` on input so we control orientation
  # explicitly; otherwise ffmpeg auto-applies the displaymatrix and we'd double-rotate.
  def rotation_filter
    case @rotation
    when 90 then 'transpose=1'
    when 180 then 'transpose=1,transpose=1'
    when 270 then 'transpose=2'
    end
  end

  # The `enable_index` form is only meaningful inside a single-pass chain, where the frame
  # counter `n` advances 0..N-1 after the `fps` filter and each drawtext fires on its own
  # tile. In the seek-and-grab path every input is a single frame, so no enable clause.
  def drawtext_filter(t, enable_index: nil)
    text = format_hms(t).gsub(':', '\\:')
    fontsize = (@thumb_width / 17.0).round
    pad = (@thumb_width / 40.0).round
    border = [(@thumb_width / 60.0).round, 1].max
    parts = ["drawtext=fontfile=#{FONT_PATH}", "text='#{text}'"]
    parts << "enable='eq(n\\,#{enable_index})'" if enable_index
    parts += ["x=#{pad}:y=h-th-#{pad}", "fontsize=#{fontsize}:fontcolor=white", "box=1:boxcolor=black@0.65:boxborderw=#{border}"]
    parts.join(':')
  end

  def seek_and_grab_args(timestamps)
    seek_inputs = timestamps.flat_map do |t|
      per_input = []
      per_input += ['-hwaccel', 'videotoolbox'] if @hwaccel
      per_input += ['-noautorotate', '-noaccurate_seek', '-ss', format('%.3f', t), '-t', '0.1', '-i', @video_path]
      per_input
    end

    seek_inputs + [
      '-filter_complex', seek_and_grab_filter_complex(timestamps),
      '-frames:v', '1',
      '-update', '1',
      *encode_output_args
    ]
  end

  def seek_and_grab_filter_complex(timestamps)
    per_input = timestamps.each_with_index.map do |t, i|
      "[#{i}:v]#{seek_and_grab_per_input_chain(t)}[v#{i}]"
    end.join(';')

    concat_inputs = (0...@frames).map { |i| "[v#{i}]" }.join
    concat_part = "#{concat_inputs}concat=n=#{@frames}:v=1[c]"
    tile_part = "[c]tile=#{@cols}x#{@rows}:padding=#{TILE_PADDING}:margin=#{TILE_MARGIN}:color=black"

    "#{per_input};#{concat_part};#{tile_part}"
  end

  def seek_and_grab_per_input_chain(t)
    [
      'select=eq(n\\,0)',
      rotation_filter,
      "scale=#{@thumb_width}:-2",
      'setsar=1',
      'setpts=PTS-STARTPTS',
      drawtext_filter(t)
    ].compact.join(',')
  end

  def run_ffmpeg(args)
    full = [MediaTools.ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-y'] + args
    stderr = `#{full.map { |a| Shellwords.escape(a) }.join(' ')} 2>&1 >/dev/null`
    raise "ffmpeg failed:\n  cmd: #{full.join(' ')}\n  stderr: #{stderr.strip}" unless $CHILD_STATUS.success?

    stderr
  end

  # Shared with ContactSheetJob — exposed as a class method so callers without
  # a ContactSheet instance can format timestamps the same way.
  def self.format_hms(seconds)
    total = seconds.to_i
    format('%02d:%02d:%02d', total / 3600, (total % 3600) / 60, total % 60)
  end

  def format_hms(seconds)
    self.class.format_hms(seconds)
  end

  # Inverse of format_hms, shared with ContactSheetJob and the CLI. Accepts a
  # Numeric, bare seconds ("12.5"), MM:SS, or HH:MM:SS — returns seconds as a Float.
  def self.parse_hms(value)
    return value.to_f if value.is_a?(Numeric)
    return value.to_f unless value.to_s.include?(':')

    parts = value.to_s.split(':').map(&:to_f)
    case parts.length
    when 3 then (parts[0] * 3600) + (parts[1] * 60) + parts[2]
    when 2 then (parts[0] * 60) + parts[1]
    else parts[0]
    end
  end

  def report(range)
    puts "Contact sheet written to #{@output_path}"
    puts "  #{@frames} frames (#{@cols}x#{@rows}) covering #{format_hms(@start_time)}-#{format_hms(@end_time)} (#{format_hms(range)})"
    detail = "codec=#{@codec} pix_fmt=#{@pix_fmt} class=#{clip_class} strategy=#{@strategy.to_s.tr('_', '-')}"
    detail += ' hwaccel=videotoolbox' if @hwaccel
    detail += " rotation=#{@rotation}" if @rotation.positive?
    detail += ' vfr=true' if @vfr
    puts "  #{detail}"
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { library: nil, output: nil }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby contact_sheet.rb <video-path> [<start>] [<end>] [--library DIR] [--output PATH]'
    opts.separator ''
    opts.separator '  <start> and <end> are optional. Omit both to cover the whole clip.'
    opts.separator '  When given, they accept seconds (e.g. 12.5) or HH:MM:SS / MM:SS.'
    opts.on('--library DIR', 'Library directory; output is saved to <library>/contact_sheets/') do |v|
      options[:library] = v
    end
    opts.on('--output PATH', 'Exact output path (overrides --library)') do |v|
      options[:output] = v
    end
  end
  parser.parse!

  video_path, start_arg, end_arg = ARGV[0], ARGV[1], ARGV[2]
  if video_path.nil? || video_path.empty?
    puts parser.help
    exit 1
  end

  begin
    ContactSheet.extract(
      video_path,
      start_arg && ContactSheet.parse_hms(start_arg),
      end_arg && ContactSheet.parse_hms(end_arg),
      library_dir: options[:library],
      output_path: options[:output]
    )
  rescue StandardError => e
    warn "contact-sheet: #{e.message}"
    exit 1
  end
end
