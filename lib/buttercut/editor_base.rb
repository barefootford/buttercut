require 'securerandom'
require 'pathname'
require 'cgi'
require 'json'
require 'digest'

class ButterCut
  # Shared functionality for editor-specific generators.
  class EditorBase
    DEFAULT_START_TIME = "0s"
    DEFAULT_INITIAL_OFFSET = "0s"
    DEFAULT_VOLUME_ADJUSTMENT = "-13.100000000000001db"

    attr_reader :clips, :initial_offset, :volume_adjustment, :sequence_frame_rate,
                :sequence_width, :sequence_height, :windows_file_paths, :audio_track,
                :audio_start

    def initialize(clips, options = {})
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
      @sequence_frame_rate = options[:sequence_frame_rate]
      @sequence_width = options[:sequence_width]
      @sequence_height = options[:sequence_height]
      @windows_file_paths = options.fetch(:windows_file_paths, false)  # Default false, Linux-first
      @audio_track = options[:audio_track]  # Optional path to audio file (music track)
      @audio_start = options[:audio_start]  # Optional start offset in seconds (e.g., skip intro)

      @metadata_cache = {}
      @clips.each do |clip|
        path = clip[:path]
        @metadata_cache[path] = extract_metadata_from_ffprobe(path)
      end

      # Cache audio track metadata if provided
      if @audio_track
        @metadata_cache[@audio_track] = extract_metadata_from_ffprobe(@audio_track)
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

    def video_width(video_path)
      metadata = extract_metadata(video_path)
      video_stream = metadata['streams'].find { |s| s['codec_type'] == 'video' }
      video_stream['width']
    end

    def video_height(video_path)
      metadata = extract_metadata(video_path)
      video_stream = metadata['streams'].find { |s| s['codec_type'] == 'video' }
      video_stream['height']
    end

    def video_duration(video_path)
      metadata = extract_metadata(video_path)
      metadata['format']['duration'].to_f
    end

    def frame_rate(video_path)
      metadata = extract_metadata(video_path)
      video_stream = metadata['streams'].find { |s| s['codec_type'] == 'video' }
      video_stream['r_frame_rate']
    end

    def frame_duration(video_path)
      rate = frame_rate(video_path)
      numerator, denominator = rate.split('/').map(&:to_i)
      "#{denominator}/#{numerator}s"
    end

    def audio_sample_rate(video_path)
      metadata = extract_metadata(video_path)
      audio_stream = metadata['streams'].find { |s| s['codec_type'] == 'audio' }
      audio_stream['sample_rate']
    end

    def audio_duration(audio_path)
      metadata = extract_metadata(audio_path)
      metadata['format']['duration'].to_f
    end

    def audio_duration_to_fraction(audio_path, frame_duration)
      duration_seconds = audio_duration(audio_path)
      frame_num, frame_denom = frame_duration.match(/(\d+)\/(\d+)/).captures.map(&:to_i)
      fps = frame_denom.to_f / frame_num

      total_frames = (duration_seconds * fps).round
      result_num = total_frames * frame_num
      result_denom = frame_denom

      divisor = gcd(result_num, result_denom)
      "#{result_num / divisor}/#{result_denom / divisor}s"
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
      (rate_num == 30000 && rate_denom == 1001) || (rate_num == 60000 && rate_denom == 1001)
    end

    def drop_frames_for_rate(fps_nominal)
      case fps_nominal
      when 60 then 4
      when 30 then 2
      else 0
      end
    end

    def color_space(video_path)
      metadata = extract_metadata(video_path)
      video_stream = metadata['streams'].find { |s| s['codec_type'] == 'video' }

      cs = video_stream['color_space']
      cp = video_stream['color_primaries']
      ct = video_stream['color_transfer']

      if cs == 'bt709' || cp == 'bt709' || ct == 'bt709'
        "1-1-1 (Rec. 709)"
      else
        "1-1-1 (Rec. 709)"
      end
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

    def format_width
      @sequence_width || video_width(@clips.first[:path])
    end

    def format_height
      @sequence_height || video_height(@clips.first[:path])
    end

    def video_rotation(video_path)
      metadata = extract_metadata(video_path)
      video_stream = metadata['streams'].find { |s| s['codec_type'] == 'video' }

      # Check side_data_list for rotation (common in mobile video)
      if video_stream['side_data_list']
        rotation_data = video_stream['side_data_list'].find { |sd| sd['rotation'] }
        return rotation_data['rotation'].to_i if rotation_data
      end

      # Check tags for rotation
      tags = video_stream['tags'] || {}
      return tags['rotate'].to_i if tags['rotate']

      0
    end

    def format_frame_duration
      return "1/#{@sequence_frame_rate}s" if @sequence_frame_rate
      frame_duration(@clips.first[:path])
    end

    def format_frame_rate
      return "#{@sequence_frame_rate}/1" if @sequence_frame_rate
      frame_rate(@clips.first[:path])
    end

    def format_nominal_frame_rate
      return @sequence_frame_rate if @sequence_frame_rate
      nominal_frame_rate(@clips.first[:path])
    end

    def format_color_space
      color_space(@clips.first[:path])
    end

    def format_audio_rate
      audio_sample_rate(@clips.first[:path])
    end

    def gcd(a, b)
      while b != 0
        a, b = b, a % b
      end
      a
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

    def round_to_frame_boundary(time_value, frame_duration)
      return "0s" if time_value == "0s" || time_value == 0
      time_value = seconds_to_fraction(time_value) if time_value.is_a?(Numeric)

      if time_value.match(/^(\d+)s$/)
        time_num = Regexp.last_match(1).to_i
        time_denom = 1
      else
        time_num, time_denom = time_value.match(/(\d+)\/(\d+)/).captures.map(&:to_i)
      end

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

      if frac1.match(/^(\d+)s$/)
        num1 = Regexp.last_match(1).to_i
        denom1 = 1
      else
        num1, denom1 = frac1.match(/(\d+)\/(\d+)/).captures.map(&:to_i)
      end

      if frac2.match(/^(\d+)s$/)
        num2 = Regexp.last_match(1).to_i
        denom2 = 1
      else
        num2, denom2 = frac2.match(/(\d+)\/(\d+)/).captures.map(&:to_i)
      end

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

      if @windows_file_paths && abs_path.start_with?('/mnt/')
        # Convert WSL/Linux path to Windows path for Premiere compatibility
        # /mnt/d/... -> D:/...
        drive_letter = abs_path[5].upcase
        windows_path = "#{drive_letter}:#{abs_path[6..]}"
        abs_path = windows_path
        "file://localhost/#{abs_path.gsub(' ', '%20')}"
      else
        "file://#{abs_path.gsub(' ', '%20')}"
      end
    end

    def escape_xml(str)
      return "" if str.nil?
      CGI.escapeHTML(str).gsub("&#39;", "&apos;")
    end

    def build_asset_map
      # Pre-scan for rotation overrides: any clip with an explicit :rotation wins for that file
      rotation_overrides = {}
      @clips.each do |clip_def|
        abs_path = get_absolute_path(clip_def[:path])
        if clip_def.key?(:rotation) && !rotation_overrides.key?(abs_path)
          rotation_overrides[abs_path] = clip_def[:rotation].to_i
        end
      end

      file_to_asset = {}
      @clips.each do |clip_def|
        video_file_path = clip_def[:path]
        abs_path = get_absolute_path(video_file_path)
        next if file_to_asset.key?(abs_path)

        asset_id = deterministic_asset_id(abs_path)
        asset_uid = deterministic_asset_uid(abs_path)
        filename = get_filename(video_file_path)
        file_url = path_to_file_url(video_file_path)

        # Use rotation override from any clip for this file, or fall back to ffprobe metadata
        rotation = rotation_overrides.fetch(abs_path) { video_rotation(video_file_path) }

        file_to_asset[abs_path] = {
          asset_id: asset_id,
          asset_uid: asset_uid,
          abs_path: abs_path,
          filename: filename,
          basename: get_basename(filename),
          file_url: file_url,
          asset_duration: duration_to_fraction(video_file_path),
          audio_rate: audio_sample_rate(video_file_path),
          timecode: clip_timecode_fraction(video_file_path),
          frame_duration: frame_duration(video_file_path),
          frame_rate: frame_rate(video_file_path),
          width: video_width(video_file_path),
          height: video_height(video_file_path),
          color_space: color_space(video_file_path),
          rotation: rotation
        }
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

    def frame_duration_rational_for(frame_duration_fraction)
      fraction_to_rational(frame_duration_fraction)
    end

    protected

    def extract_metadata_from_ffprobe(video_path)
      json_output = `ffprobe -v quiet -print_format json -show_format -show_streams "#{video_path}" 2>&1`

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
