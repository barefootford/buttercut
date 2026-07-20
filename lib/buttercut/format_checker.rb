# frozen_string_literal: true

require 'English'
require 'json'
require 'shellwords'

require_relative 'media_tools'
require_relative 'rotation_metadata'

# Probes a set of video files and reports whether they all share one format —
# display resolution (rotation-aware, so a portrait phone clip reads as
# 1080x1920, not 1920x1080) and frame rate. Mixing formats is always allowed:
# this is a heads-up, never a gate. When clips land on a single-track timeline
# the editor conforms everything to the timeline format, and the symptoms
# (soft scaled footage, black bars, stuttery retimed motion) confuse users who
# don't know their footage was mixed — so ButterCut surfaces it after
# processing (`Library#format_report`) and again at export.
#
# Audio sample rate is tracked as a secondary signal: it never makes clips
# "mixed" on its own (silent drone clips next to mic'd clips would false-flag
# constantly), but distinct non-nil rates are reported.
#
# Read-only: inspects files via ffprobe, never writes. A clip that can't be
# probed (missing file, no video stream, broken rate) becomes an `error` row
# and is excluded from the format grouping rather than failing the report.
# `prober` is injectable so the grouping logic is testable without ffprobe.
class FormatChecker
  include RotationMetadata

  def initialize(paths, prober: nil)
    @paths = Array(paths)
    @prober = prober || method(:ffprobe_streams)
  end

  # Per-clip rows in input order. Probed clips carry 'resolution' (display,
  # e.g. "1920x1080"), 'fps' (label, e.g. "29.97"), 'frame_rate' (exact
  # fraction, e.g. "30000/1001"), and 'audio_sample_rate' (nil when silent);
  # unprobeable clips carry an 'error' string instead.
  def clips
    @clips ||= @paths.map { |path| clip_row(path) }
  end

  def readable   = clips.reject { |c| c['error'] }
  def unreadable = clips.select { |c| c['error'] }

  # Distinct resolution+fps combinations among readable clips, biggest group
  # first (ties keep input order — Ruby's sort_by isn't stable on its own).
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
  # nil when the formats are uniform. The caller supplies the subject ("This
  # cut", "This footage") and appends its own advice.
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

    width, height = display_dimensions(video)
    return row.merge('error' => 'unreadable dimensions') if width.zero? || height.zero?

    fraction = video['r_frame_rate'].to_s
    numerator, denominator = fraction.split('/').map(&:to_i)
    if numerator.nil? || denominator.nil? || numerator.zero? || denominator.zero?
      return row.merge('error' => "unreadable frame rate: #{fraction.inspect}")
    end

    audio = Array(data['streams']).find { |s| s['codec_type'] == 'audio' }
    row.merge(
      'resolution' => "#{width}x#{height}",
      'fps' => fps_label(numerator, denominator),
      'frame_rate' => fraction,
      'audio_sample_rate' => audio && audio['sample_rate']&.to_i
    )
  end

  # Stored width/height swapped when rotation metadata says the clip displays
  # sideways — what matters for mixing is how the clip fills the timeline.
  def display_dimensions(stream)
    width = stream['width'].to_i
    height = stream['height'].to_i
    [90, 270].include?(extract_rotation(stream)) ? [height, width] : [width, height]
  end

  # "30000/1001" → "29.97", "25/1" → "25" — decimals only when the rate has them.
  def fps_label(numerator, denominator)
    fps = (numerator.to_f / denominator).round(2)
    (fps == fps.to_i ? fps.to_i : fps).to_s
  end

  def ffprobe_streams(path)
    output = `#{Shellwords.escape(MediaTools.ffprobe)} -v error -print_format json -show_streams #{Shellwords.escape(path)} 2>&1`
    raise "ffprobe failed: #{output.strip}" unless $CHILD_STATUS.success?

    JSON.parse(output)
  end
end
