require 'securerandom'
require 'pathname'
require 'cgi'
require 'erb'
require 'json'
require 'digest'
require 'shellwords'
require_relative 'rotation_metadata'
require_relative 'media_tools'
require_relative 'library'

class ButterCut
  # Shared functionality for editor-specific generators.
  class EditorBase
    extend RotationMetadata

    DEFAULT_START_TIME = "0s"
    DEFAULT_INITIAL_OFFSET = "0s"
    DEFAULT_VOLUME_ADJUSTMENT = "-13.100000000000001db"

    attr_reader :clips, :initial_offset, :volume_adjustment

    # `timeline:` is an optional explicit output format (from the cut YAML's
    # `timeline:` block): frame_rate (fraction string or number), width,
    # height. Anything not given falls back to the first video clip, and —
    # for image-only timelines — to 24fps 1920×1080.
    def initialize(clips, timeline: nil)
      raise ArgumentError, "No clips provided" if clips.nil? || clips.empty?

      clips.each_with_index do |clip, index|
        unless clip.is_a?(Hash)
          raise ArgumentError, "Clip at index #{index} must be a hash, got #{clip.class}"
        end
        unless clip.key?(:path)
          raise ArgumentError, "Clip at index #{index} must have a 'path' key"
        end
        if image_clip?(clip) && clip[:duration].nil?
          raise ArgumentError, "Image clip at index #{index} (#{clip[:path]}) must have a 'duration' key — stills are timeless"
        end
      end

      relative_paths = clips.select { |clip| !Pathname.new(clip[:path]).absolute? }
      unless relative_paths.empty?
        paths = relative_paths.map { |clip| clip[:path] }.join(', ')
        raise ArgumentError, "All media file paths must be absolute paths. Relative paths found: #{paths}"
      end

      @clips = clips
      @timeline = normalize_timeline(timeline)
      @initial_offset = DEFAULT_INITIAL_OFFSET
      @volume_adjustment = DEFAULT_VOLUME_ADJUSTMENT

      @metadata_cache = {}
      @clips.each do |clip|
        path = clip[:path]
        @metadata_cache[path] = extract_metadata_from_ffprobe(path)
      end
    end

    # A clip's media type: explicit :type wins (Export sets it), otherwise
    # inferred from the extension via the registry's one owner. Unknown
    # extensions read as video, matching Library's lenient-read rule.
    def clip_type(clip)
      (clip[:type] || Library.media_type_of(clip[:path]) || 'video').to_s
    end

    def image_clip?(clip) = clip_type(clip) == 'image'

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

    # nil when the source has no audio stream (stills, video-only recordings) —
    # callers fall back to the 48000 default.
    def audio_sample_rate(video_path)
      audio_stream(video_path)&.fetch('sample_rate', nil)
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

    # The first video (not image) clip on the timeline — the source the output
    # format is derived from when the cut YAML doesn't pin one explicitly.
    # nil for image-only timelines.
    def first_video_path
      @first_video_path ||= @clips.find { |clip| !image_clip?(clip) }&.fetch(:path)
    end

    # Output format resolution, three tiers: explicit `timeline:` block from
    # the cut YAML → first video clip → image-only defaults (24fps, 1920×1080,
    # 48kHz). The cut skill is supposed to always write the block for
    # image-only cuts, so the last tier is a safety net, not a policy.
    def format_width
      @timeline[:width] || source_format_width
    end

    def format_height
      @timeline[:height] || source_format_height
    end

    def source_format_width
      first_video_path ? video_width(first_video_path) : 1920
    end

    def source_format_height
      first_video_path ? video_height(first_video_path) : 1080
    end

    def format_frame_rate
      @timeline[:frame_rate] || (first_video_path ? frame_rate(first_video_path) : '24/1')
    end

    def format_frame_duration
      numerator, denominator = format_frame_rate.split('/').map(&:to_i)
      "#{denominator}/#{numerator}s"
    end

    def format_nominal_frame_rate
      rate_num, rate_denom = format_frame_rate.split('/').map(&:to_i)
      return 0 if rate_denom.zero?

      (rate_num.to_f / rate_denom).round
    end

    def format_color_space
      color_space(first_video_path)
    end

    def format_audio_rate
      (first_video_path && audio_sample_rate(first_video_path)) || '48000'
    end

    # Accept a frame rate as a fraction string ("30000/1001"), an integer, or
    # the conventional NTSC decimals (23.976/29.97/59.94) and normalize to the
    # exact fraction every internal computation expects.
    def self.frame_rate_fraction(value)
      str = value.to_s.strip
      return str if str.include?('/')

      rate = Float(str)
      { 23.976 => '24000/1001', 29.97 => '30000/1001', 59.94 => '60000/1001' }.each do |decimal, fraction|
        return fraction if (rate - decimal).abs < 0.005
      end
      raise ArgumentError, "frame_rate must be a whole number, an NTSC rate, or a fraction; got #{value.inspect}" unless (rate - rate.round).abs < 0.001

      "#{rate.round}/1"
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

    # RFC 2396/3986 file URL: every path segment percent-encoded (UTF-8 bytes,
    # spaces, parens, #, &, …), slashes preserved. Editors resolve `src` /
    # `pathurl` strictly — a single unescaped reserved character imports as
    # offline ("missing") media.
    def path_to_file_url(path)
      abs_path = get_absolute_path(path)
      encoded = abs_path.split('/', -1).map { |segment| ERB::Util.url_encode(segment) }.join('/')
      "file://#{encoded}"
    end

    def escape_xml(str)
      return "" if str.nil?
      CGI.escapeHTML(str).gsub("&#39;", "&apos;")
    end

    # One asset record per unique source file. Stills are timeless: only
    # dimensions are probed — no duration, audio rate, timecode, frame rate,
    # or rotation keys at all (generators branch on :type).
    def build_asset_map
      file_to_asset = {}
      @clips.each do |clip_def|
        media_file_path = clip_def[:path]
        abs_path = get_absolute_path(media_file_path)
        next if file_to_asset.key?(abs_path)

        filename = get_filename(media_file_path)
        asset = {
          asset_id: deterministic_asset_id(abs_path),
          asset_uid: deterministic_asset_uid(abs_path),
          abs_path: abs_path,
          filename: filename,
          basename: get_basename(filename),
          file_url: path_to_file_url(media_file_path),
          type: clip_type(clip_def),
          width: video_width(media_file_path),
          height: video_height(media_file_path)
        }

        if asset[:type] != 'image'
          asset.merge!(
            asset_duration: duration_to_fraction(media_file_path),
            audio_rate: audio_sample_rate(media_file_path),
            timecode: clip_timecode_fraction(media_file_path),
            frame_duration: frame_duration(media_file_path),
            frame_rate: frame_rate(media_file_path),
            rotation: video_rotation(media_file_path),
            color_space: color_space(media_file_path)
          )
        end

        file_to_asset[abs_path] = asset
      end
      file_to_asset
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

    def normalize_timeline(timeline)
      return {} if timeline.nil?

      normalized = {}
      frame_rate = timeline[:frame_rate] || timeline['frame_rate']
      normalized[:frame_rate] = self.class.frame_rate_fraction(frame_rate) if frame_rate
      width = timeline[:width] || timeline['width']
      normalized[:width] = Integer(width) if width
      height = timeline[:height] || timeline['height']
      normalized[:height] = Integer(height) if height
      normalized
    end

    def extract_metadata_from_ffprobe(video_path)
      json_output = `#{Shellwords.escape(MediaTools.ffprobe)} -v quiet -print_format json -show_format -show_streams "#{video_path}" 2>&1`

      if $?.exitstatus != 0
        raise "Failed to extract metadata from #{video_path}: #{json_output}"
      end

      JSON.parse(json_output)
    end

    def compute_clip_duration(clip_def, asset_info, start_at, asset_frame_duration, timeline_frame_duration)
      duration = if clip_def[:duration]
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
