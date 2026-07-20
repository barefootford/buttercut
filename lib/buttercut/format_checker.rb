# frozen_string_literal: true

require_relative 'media_tools'
require_relative 'rotation_metadata'

# Probes video files via ffprobe and reports whether they all share one format:
# rotation-aware display resolution + frame rate, with audio sample rate as a
# secondary signal that never splits formats on its own. Mixing is allowed —
# this is a heads-up, never a gate. Read-only; unprobeable clips become `error`
# rows instead of failures, and `prober` is injectable for ffprobe-free tests.
class FormatChecker
  include RotationMetadata

  # "30000/1001" → "29.97", "25/1" → "25" — decimals only when the rate has
  # them. The one owner of the human fps label, shared with the export notice.
  def self.fps_label(fraction)
    numerator, denominator = fraction.to_s.split('/').map(&:to_i)
    fps = (numerator.to_f / denominator).round(2)
    (fps == fps.to_i ? fps.to_i : fps).to_s
  end

  def initialize(paths, prober: nil)
    @paths = Array(paths)
    @prober = prober || ->(path) { MediaTools.ffprobe_json(path, 'streams') }
  end

  # Per-clip rows in input order: 'resolution', 'fps' label, 'frame_rate'
  # fraction, 'audio_sample_rate' (nil = silent) — or an 'error' string.
  def clips
    @clips ||= @paths.map { |path| clip_row(path) }
  end

  def readable   = clips.reject { |c| c['error'] }
  def unreadable = clips.select { |c| c['error'] }

  # Distinct resolution+fps combos among readable clips, biggest group first
  # (ties keep input order — Ruby's sort_by isn't stable on its own).
  def formats
    @formats ||= readable
                 .group_by { |c| [c['resolution'], c['fps']] }
                 .map do |(resolution, fps), rows|
                   { 'resolution' => resolution, 'fps' => fps,
                     'frame_rate' => rows.first['frame_rate'],
                     'count' => rows.size, 'clips' => rows.map { |r| r['filename'] } }
                 end
                 .each_with_index.sort_by { |format, index| [-format['count'], index] }
                 .map(&:first)
  end

  def uniform?  = formats.size <= 1
  def dominant  = formats.first
  def outliers  = formats.drop(1).flat_map { |f| f['clips'] }

  def audio_sample_rates = readable.filter_map { |c| c['audio_sample_rate'] }.uniq
  def mixed_audio?       = audio_sample_rates.size > 1

  # The full JSON report `library.rb <name> format_report` prints.
  def report
    {
      'clips' => clips,
      'formats' => formats,
      'uniform' => uniform?,
      'dominant_format' => dominant,
      'outlier_clips' => outliers,
      'mixed_audio_sample_rates' => mixed_audio? ? audio_sample_rates : [],
      'unreadable' => unreadable
    }
  end

  # One editor-friendly sentence listing each format group with its clips, or
  # nil when uniform. Callers supply the subject and append their own advice.
  def mixed_summary(subject: 'This footage')
    return nil if uniform?

    groups = formats.map do |f|
      noun = f['count'] == 1 ? 'clip' : 'clips'
      "#{f['resolution']} @ #{f['fps']}fps (#{f['count']} #{noun}: #{f['clips'].join(', ')})"
    end
    "#{subject} mixes #{formats.size} formats: #{groups.join('; ')}."
  end

  private

  def clip_row(path)
    row = { 'filename' => File.basename(path), 'path' => path }
    return row.merge('error' => 'file not found') unless File.exist?(path)

    stream_row(row, @prober.call(path))
  rescue StandardError => e
    row.merge('error' => e.message)
  end

  def stream_row(row, data)
    video = Array(data['streams']).find { |s| s['codec_type'] == 'video' }
    return row.merge('error' => 'no video stream') unless video

    width, height = display_dimensions(video['width'].to_i, video['height'].to_i, extract_rotation(video))
    return row.merge('error' => 'unreadable dimensions') if width.zero? || height.zero?

    fraction = video['r_frame_rate'].to_s
    numerator, denominator = fraction.split('/').map(&:to_i)
    if numerator.nil? || denominator.nil? || numerator.zero? || denominator.zero?
      return row.merge('error' => "unreadable frame rate: #{fraction.inspect}")
    end

    audio = Array(data['streams']).find { |s| s['codec_type'] == 'audio' }
    row.merge(
      'resolution' => "#{width}x#{height}",
      'fps' => self.class.fps_label(fraction),
      'frame_rate' => fraction,
      'audio_sample_rate' => audio && audio['sample_rate']&.to_i
    )
  end
end
