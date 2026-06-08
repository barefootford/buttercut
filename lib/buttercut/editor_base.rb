require 'securerandom'
require 'pathname'
require 'cgi'
require 'json'
require 'digest'
require 'shellwords'
require_relative 'rotation_metadata'
require_relative 'media'
require_relative 'media_tools'

class ButterCut
  # Shared functionality for editor-specific generators.
  class EditorBase
    extend RotationMetadata

    DEFAULT_START_TIME = "0s"
    DEFAULT_INITIAL_OFFSET = "0s"
    DEFAULT_VOLUME_ADJUSTMENT = "-13.100000000000001db"

    # Stills have no source frame rate or audio. When a still leads the timeline
    # (so there's no video to inherit the format from) the sequence falls back to
    # a plain 24fps grid, and a still clip given no in/out holds for this long.
    # The 4s hold is a safety net, not the planning default — cut YAMLs set an
    # explicit in/out per still (see skills/cut/cut_yaml_schema.md, which
    # documents this fallback), so it fires only for a missing/zero-length span.
    DEFAULT_FRAME_RATE = "24/1"
    DEFAULT_FRAME_DURATION = "1/24s"
    DEFAULT_NOMINAL_FRAME_RATE = 24
    DEFAULT_IMAGE_DURATION = 4.0 # seconds

    attr_reader :clips, :initial_offset, :volume_adjustment

    def initialize(clips)
      raise ArgumentError, "No clips provided" if clips.nil? || clips.empty?

      clips.each_with_index do |clip, index|
        unless clip.is_a?(Hash)
          raise ArgumentError, "Clip at index #{index} must be a hash, got #{clip.class}"
        end
        unless clip.key?(:path)
          raise ArgumentError, "Clip at index #{index} must have a 'path' key"
        end
      end

      relative_paths = clips.select { |clip| !Pathname.new(clip[:path]).absolute? }
      unless relative_paths.empty?
        paths = relative_paths.map { |clip| clip[:path] }.join(', ')
        raise ArgumentError, "All video file paths must be absolute paths. Relative paths found: #{paths}"
      end

      @clips = clips
      @initial_offset = DEFAULT_INITIAL_OFFSET
      @volume_adjustment = DEFAULT_VOLUME_ADJUSTMENT

      # ||= so a source that appears at several points on the timeline (common
      # for a reused still) is probed once, not once per occurrence.
      @metadata_cache = {}
      @clips.each do |clip|
        path = clip[:path]
        @metadata_cache[path] ||= extract_metadata_from_ffprobe(path)
      end
    end

    def save(filename)
      File.write(filename, to_xml)
    end

    def generate_uuid
      SecureRandom.uuid
    end

    def extract_metadata(video_path)
      @metadata_cache[video_path]
    end

    def video_stream(video_path)
      extract_metadata(video_path)['streams'].find { |s| s['codec_type'] == 'video' }
    end

    def audio_stream(video_path)
      extract_metadata(video_path)['streams'].find { |s| s['codec_type'] == 'audio' }
    end

    def video_width(video_path)
      video_stream(video_path)['width']
    end

    def video_height(video_path)
      video_stream(video_path)['height']
    end

    # Degrees clockwise (0/90/180/270) the source must be rotated to display upright,
    # read from container rotation metadata via RotationMetadata.
    def video_rotation(video_path)
      self.class.extract_rotation(video_stream(video_path))
    end

    def video_duration(video_path)
      metadata = extract_metadata(video_path)
      metadata['format']['duration'].to_f
    end

    def frame_rate(video_path)
      video_stream(video_path)['r_frame_rate']
    end

    def frame_duration(video_path)
      rate = frame_rate(video_path)
      numerator, denominator = rate.split('/').map(&:to_i)
      "#{denominator}/#{numerator}s"
    end

    # nil when the source has no audio stream (e.g. a still image), so callers
    # can fall back rather than crash on a missing stream.
    def audio_sample_rate(video_path)
      audio_stream(video_path)&.[]('sample_rate')
    end

    def nominal_frame_rate(video_path)
      rate_num, rate_denom = frame_rate(video_path).split('/').map(&:to_i)
      return 0 if rate_denom.zero?

      (rate_num.to_f / rate_denom).round
    end

    def clip_timecode_string(video_path)
      metadata = extract_metadata(video_path)

      if metadata['streams']
        metadata['streams'].each do |stream|
          tags = stream['tags']
          next unless tags && tags['timecode'] && !tags['timecode'].empty?

          return tags['timecode']
        end
      end

      format_tags = metadata.dig('format', 'tags')
      if format_tags
        tc = format_tags['timecode']
        return tc unless tc.nil? || tc.empty?

        panasonic_xml = format_tags['com.panasonic.Semi-Pro.metadata.xml']
        if panasonic_xml
          match = panasonic_xml.match(/<StartTimecode>([^<]+)<\/StartTimecode>/)
          return match[1].strip if match
        end
      end

      nil
    end

    def clip_timecode_fraction(video_path)
      timecode = clip_timecode_string(video_path)
      return "0s" if timecode.nil? || timecode.strip.empty?

      parts = timecode.strip.tr(';', ':').split(':').map(&:to_i)
      return "0s" unless parts.length == 4

      hours, minutes, seconds, frames = parts
      fps_nominal = nominal_frame_rate(video_path)
      return "0s" if fps_nominal <= 0

      rate_num, rate_denom = frame_rate(video_path).split('/').map(&:to_i)
      return "0s" if rate_denom.zero? || rate_num.zero?

      drop_frame = drop_frame_timecode?(timecode, rate_num, rate_denom, fps_nominal)

      total_frames = if drop_frame
        drop_frames_per_minute = drop_frames_for_rate(fps_nominal)
        total_minutes = hours * 60 + minutes
        dropped_frames = drop_frames_per_minute * (total_minutes - (total_minutes / 10))
        (((hours * 3600 + minutes * 60 + seconds) * fps_nominal) + frames) - dropped_frames
      else
        ((hours * 3600 + minutes * 60 + seconds) * fps_nominal) + frames
      end

      return "0s" if total_frames.negative?

      start_num = total_frames * rate_denom
      start_denom = rate_num

      divisor = gcd(start_num, start_denom)
      "#{start_num / divisor}/#{start_denom / divisor}s"
    end

    def drop_frame_timecode?(timecode, rate_num, rate_denom, fps_nominal)
      return false unless timecode.include?(';')
      return false unless fps_nominal == 30 || fps_nominal == 60
      ntsc_drop_frame_rate?(rate_num, rate_denom)
    end

    # NTSC fractional rates (29.97 / 59.94) that use drop-frame timecode.
    def ntsc_drop_frame_rate?(rate_num, rate_denom)
      (rate_num == 30000 && rate_denom == 1001) || (rate_num == 60000 && rate_denom == 1001)
    end

    def drop_frames_for_rate(fps_nominal)
      case fps_nominal
      when 60 then 4
      when 30 then 2
      else 0
      end
    end

    # Color space is currently always emitted as Rec. 709; non-709 sources
    # (HDR / Rec. 2020, P3) are not yet mapped. Takes a path for signature
    # parity with the other per-clip metadata accessors.
    def color_space(_video_path)
      "1-1-1 (Rec. 709)"
    end

    def duration_to_fraction(video_path)
      duration_seconds = video_duration(video_path)
      rate = frame_rate(video_path)
      numerator, denominator = rate.split('/').map(&:to_i)

      total_frames = (duration_seconds * numerator / denominator).round

      duration_num = total_frames * denominator
      duration_denom = numerator

      divisor = gcd(duration_num, duration_denom)
      "#{duration_num / divisor}/#{duration_denom / divisor}s"
    end

    # The first clip drives the timeline format (frame rate, dimensions, …).
    def first_clip_path = @clips.first[:path]

    # True when a still leads the timeline. A still has no source frame rate or
    # dimensions, so a leading still makes the format fall back to defaults here
    # (and makes Premiere skip its rotation swap).
    def leading_image? = Media.image?(first_clip_path)

    def format_width
      video_width(first_clip_path)
    end

    def format_height
      video_height(first_clip_path)
    end

    # The timeline format follows the first clip. A still has no source frame
    # rate, so when it leads, fall back to the 24fps default; later stills then
    # inherit this timeline rate via build_asset_map.
    def format_frame_duration
      leading_image? ? DEFAULT_FRAME_DURATION : frame_duration(first_clip_path)
    end

    def format_frame_rate
      leading_image? ? DEFAULT_FRAME_RATE : frame_rate(first_clip_path)
    end

    def format_nominal_frame_rate
      leading_image? ? DEFAULT_NOMINAL_FRAME_RATE : nominal_frame_rate(first_clip_path)
    end

    def format_color_space
      color_space(first_clip_path)
    end

    def format_audio_rate
      audio_sample_rate(first_clip_path)
    end

    # Greatest Common Divisor (GCD): the largest whole number that divides two
    # integers evenly — e.g. gcd(25000, 10000) is 5000. ButterCut tracks every
    # timeline duration and offset as an exact `numerator/denominators` fraction
    # (the format Final Cut's XML uses), and those numbers balloon as the math
    # compounds. Dividing both halves of a fraction by their GCD puts it back in
    # lowest terms — 25000/10000s becomes 5/2s — keeping the values small and the
    # output clean. Ruby's built-in Integer#gcd does the arithmetic.
    def gcd(a, b)
      a.gcd(b)
    end

    def add_fractions(frac1, frac2)
      return frac2 if frac1 == "0s"
      return frac1 if frac2 == "0s"

      num1, denom1 = frac1.match(/(\d+)\/(\d+)/).captures.map(&:to_i)
      num2, denom2 = frac2.match(/(\d+)\/(\d+)/).captures.map(&:to_i)

      result_num = num1 * denom2 + num2 * denom1
      result_denom = denom1 * denom2

      divisor = gcd(result_num, result_denom)
      result_num /= divisor
      result_denom /= divisor

      "#{result_num}/#{result_denom}s"
    end

    def time_value_zero?(value)
      return true if value.nil?
      return true if value == 0 || value == 0.0
      return true if value == "0s"
      false
    end

    def seconds_to_fraction(seconds)
      return "0s" if seconds == 0 || seconds == "0s"
      return seconds if seconds.is_a?(String)
      seconds = seconds.to_f if seconds.is_a?(Integer)

      denominator = 10000
      numerator = (seconds * denominator).round
      divisor = gcd(numerator, denominator)
      "#{numerator / divisor}/#{denominator / divisor}s"
    end

    # Parse a duration fraction ("N/Ds" or bare "Ns") into [numerator, denominator].
    def fraction_parts(value)
      if (match = value.match(/^(\d+)s$/))
        [match[1].to_i, 1]
      else
        value.match(/(\d+)\/(\d+)/).captures.map(&:to_i)
      end
    end

    def round_to_frame_boundary(time_value, frame_duration)
      return "0s" if time_value == "0s" || time_value == 0
      time_value = seconds_to_fraction(time_value) if time_value.is_a?(Numeric)

      time_num, time_denom = fraction_parts(time_value)

      frame_num, frame_denom = frame_duration.match(/(\d+)\/(\d+)/).captures.map(&:to_i)

      frames_exact = (time_num * frame_denom).to_f / (time_denom * frame_num)
      frames_rounded = frames_exact.round

      result_num = frames_rounded * frame_num
      result_denom = frame_denom

      divisor = gcd(result_num, result_denom)
      "#{result_num / divisor}/#{result_denom / divisor}s"
    end

    def subtract_fractions(frac1, frac2)
      frac1 = seconds_to_fraction(frac1) if frac1.is_a?(Numeric)
      frac2 = seconds_to_fraction(frac2) if frac2.is_a?(Numeric)

      return frac1 if frac2 == "0s"
      return "0s" if frac1 == frac2

      num1, denom1 = fraction_parts(frac1)
      num2, denom2 = fraction_parts(frac2)

      result_num = num1 * denom2 - num2 * denom1
      result_denom = denom1 * denom2

      return "0s" if result_num <= 0

      divisor = gcd(result_num, result_denom)
      result_num /= divisor
      result_denom /= divisor

      "#{result_num}/#{result_denom}s"
    end

    def get_filename(path)
      File.basename(path)
    end

    def get_basename(filename)
      File.basename(filename, File.extname(filename))
    end

    def get_absolute_path(path)
      File.expand_path(path)
    end

    def path_to_file_url(path)
      abs_path = get_absolute_path(path)
      "file://#{abs_path.gsub(' ', '%20')}"
    end

    def escape_xml(str)
      return "" if str.nil?
      CGI.escapeHTML(str).gsub("&#39;", "&apos;")
    end

    def build_asset_map
      file_to_asset = {}
      @clips.each do |clip_def|
        media_file_path = clip_def[:path]
        abs_path = get_absolute_path(media_file_path)
        next if file_to_asset.key?(abs_path)

        filename = get_filename(media_file_path)
        image = Media.image?(media_file_path)

        # A still has no source frame rate or audio. Give it the timeline's frame
        # grid (so frame math stays valid), drop the audio rate, and size the
        # intrinsic duration to cover the clip(s) that use it rather than reading
        # a (nonexistent) container duration.
        asset_frame_duration = image ? format_frame_duration : frame_duration(media_file_path)
        asset_frame_rate     = image ? format_frame_rate     : frame_rate(media_file_path)

        # `audio_rate` is nil whenever the source has no audio stream — a still
        # (no audio at all) AND a silent video both fall out of audio_sample_rate
        # as nil, so no type branch is needed here. `has_audio` (below) drives
        # every audio branch in the writers, so a silent video is treated like a
        # still for audio purposes (hasAudio=0, no audioRate, no audio
        # clipitem/link) rather than emitting a dangling/empty audio rate.
        # Frame-rate, duration, and rotation still branch on `image`, since a
        # silent video — unlike a still — does have a real source frame rate and
        # intrinsic length.
        audio_rate = audio_sample_rate(media_file_path)

        file_to_asset[abs_path] = {
          asset_id: deterministic_asset_id(abs_path),
          asset_uid: deterministic_asset_uid(abs_path),
          abs_path: abs_path,
          filename: filename,
          basename: get_basename(filename),
          file_url: path_to_file_url(media_file_path),
          image: image,
          has_audio: !audio_rate.nil?,
          asset_duration: image ? image_asset_duration(abs_path, asset_frame_duration) : duration_to_fraction(media_file_path),
          audio_rate: audio_rate,
          timecode: clip_timecode_fraction(media_file_path),
          frame_duration: asset_frame_duration,
          frame_rate: asset_frame_rate,
          width: video_width(media_file_path),
          height: video_height(media_file_path),
          rotation: video_rotation(media_file_path),
          color_space: color_space(media_file_path)
        }
      end
      file_to_asset
    end

    # A still's asset has no intrinsic length, so size it to cover the longest
    # clip that references it (start offset + on-spine duration). That keeps every
    # clip's source in/out inside the asset bounds. (A clip with no explicit
    # duration contributes the default hold — see image_hold_seconds.)
    def image_asset_duration(abs_path, frame_duration_fraction)
      @clips_by_abs_path ||= @clips.group_by { |c| get_absolute_path(c[:path]) }
      spans = @clips_by_abs_path.fetch(abs_path).map do |clip_def|
        seconds_value(clip_def[:start_at]) + image_hold_seconds(clip_def)
      end
      round_to_frame_boundary(spans.max, frame_duration_fraction)
    end

    # A still's on-screen hold, in seconds: the cut's in/out span when it's
    # positive, else DEFAULT_IMAGE_DURATION. The fallback covers both no in/out at
    # all and a zero-length in==out span (0.0 is truthy in Ruby, so it can't be
    # caught by a plain `clip_def[:duration] ? …`). compute_clip_duration and
    # image_asset_duration share this rule so the clip's hold and the asset it
    # references stay the same length.
    def image_hold_seconds(clip_def)
      seconds = seconds_value(clip_def[:duration])
      seconds.positive? ? seconds : DEFAULT_IMAGE_DURATION
    end

    # Seconds from a clip time value that may be a Numeric (seconds) or a
    # fraction string ("N/Ds" / "Ns" / "0s"); nil → 0. The Numeric fast path is
    # deliberate: routing through fraction_to_rational would quantize to 1/10000s
    # (seconds_to_fraction), while to_f keeps the value exact.
    def seconds_value(value)
      return 0.0 if value.nil?
      return value.to_f if value.is_a?(Numeric)

      fraction_to_rational(value).to_f
    end

    def build_timeline_clips(asset_map, timeline_frame_duration)
      current_offset = initial_offset
      clips = @clips.map do |clip_def|
        abs_path = get_absolute_path(clip_def[:path])
        asset_info = asset_map.fetch(abs_path)
        asset_frame_duration = asset_info[:frame_duration] || timeline_frame_duration

        start_at_raw = clip_def[:start_at] || DEFAULT_START_TIME
        start_at = round_to_frame_boundary(start_at_raw, asset_frame_duration)

        base_timecode = asset_info[:timecode] || "0s"
        clip_start = add_fractions(base_timecode, start_at)

        duration_info = compute_clip_duration(clip_def, asset_info, start_at, asset_frame_duration, timeline_frame_duration)

        clip_data = {
          asset: asset_info,
          asset_id: asset_info[:asset_id],
          filename: asset_info[:filename],
          start: clip_start,
          duration: duration_info[:timeline],
          source_duration: duration_info[:asset],
          timeline_offset: current_offset,
          source_in: start_at,
          clip_definition: clip_def
        }

        current_offset = add_fractions(current_offset, clip_data[:duration])
        clip_data
      end

      [clips, current_offset]
    end

    def fraction_to_rational(value)
      value = seconds_to_fraction(value) if value.is_a?(Numeric)
      return Rational(0, 1) if value == "0s"

      if (match = value.match(%r{\A(\d+)\/(\d+)s\z}))
        Rational(match[1].to_i, match[2].to_i)
      elsif (match = value.match(%r{\A(\d+)s\z}))
        Rational(match[1].to_i, 1)
      else
        raise ArgumentError, "Unsupported time format: #{value.inspect}"
      end
    end

    def frames_for_fraction(duration_fraction, frame_duration_fraction)
      duration_rational = fraction_to_rational(duration_fraction)
      frame_rational = fraction_to_rational(frame_duration_fraction)
      ((duration_rational / frame_rational).round).to_i
    end

    protected

    def extract_metadata_from_ffprobe(video_path)
      json_output = `#{Shellwords.escape(MediaTools.ffprobe)} -v quiet -print_format json -show_format -show_streams "#{video_path}" 2>&1`

      if $?.exitstatus != 0
        raise "Failed to extract metadata from #{video_path}: #{json_output}"
      end

      JSON.parse(json_output)
    end

    def compute_clip_duration(clip_def, asset_info, start_at, asset_frame_duration, timeline_frame_duration)
      duration = if asset_info[:image]
        # A still has no source length; its hold is the cut's in/out span, or the
        # default when that span is missing or zero-length (see image_hold_seconds).
        image_hold_seconds(clip_def)
      elsif clip_def[:duration]
        clip_def[:duration]
      elsif clip_def[:start_at] && !time_value_zero?(clip_def[:start_at])
        subtract_fractions(asset_info[:asset_duration], start_at)
      else
        asset_info[:asset_duration]
      end

      asset_aligned = round_to_frame_boundary(duration, asset_frame_duration)
      timeline_aligned = round_to_frame_boundary(asset_aligned, timeline_frame_duration)

      {
        asset: asset_aligned,
        timeline: timeline_aligned
      }
    end

    def timestamp_suffix
      @timestamp_suffix ||= Time.now.utc.strftime("%Y%m%d-%H%M%S")
    end

    def deterministic_asset_id(abs_path)
      digest = Digest::MD5.hexdigest(abs_path)
      "r#{digest}"
    end

    def deterministic_asset_uid(abs_path)
      digest = Digest::MD5.hexdigest(abs_path)
      [
        digest[0, 8],
        digest[8, 4],
        digest[12, 4],
        digest[16, 4],
        digest[20, 12]
      ].join('-')
    end
  end
end
