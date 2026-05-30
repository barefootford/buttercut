#!/usr/bin/env ruby
# Export rough cut YAML to editor XML using ButterCut

require 'date'
require 'optparse'
require 'yaml'
require_relative '../buttercut'

class Export
  EDITOR_LABELS = {
    fcpx: 'Final Cut Pro X',
    resolve: 'DaVinci Resolve (FCP7 XML)',
    premiere: 'Adobe Premiere Pro (FCP7 XML + rotation)'
  }.freeze

  def self.perform(roughcut_path:, output_path:, editor: 'fcpx')
    new(roughcut_path: roughcut_path, output_path: output_path, editor: editor).perform
  end

  def initialize(roughcut_path:, output_path:, editor:)
    raise ArgumentError, 'roughcut_path is required' if roughcut_path.nil? || roughcut_path.empty?
    raise ArgumentError, 'output_path is required'   if output_path.nil?   || output_path.empty?
    raise ArgumentError, 'editor is required'        if editor.nil?        || editor.to_s.empty?

    @roughcut_path = roughcut_path
    @output_path   = output_path
    @editor        = resolve_editor(editor.to_s)
  end

  # A still has no intrinsic duration; this is how long it sits on the timeline
  # unless the clip overrides it.
  DEFAULT_IMAGE_DURATION_SECONDS = 5.0

  def perform
    roughcut    = load_yaml(@roughcut_path)
    library     = load_library(@roughcut_path)
    video_index = index_videos(library)
    clips       = build_clips(roughcut, video_index)

    write_xml(clips, @editor)
    validate_fcpxml(@output_path) if @editor == :fcpx
    @output_path
  end

  private

  def load_yaml(path)
    raise "Rough cut file not found: #{path}" unless File.exist?(path)

    YAML.load_file(path, permitted_classes: [Date, Time, Symbol])
  end

  def load_library(roughcut_path)
    match = roughcut_path.match(%r{libraries/([^/]+)/cuts})
    raise "Could not extract library name from path: #{roughcut_path}" unless match

    library_yaml = "libraries/#{match[1]}/library.yaml"
    raise "Library file not found: #{library_yaml}" unless File.exist?(library_yaml)

    load_yaml(library_yaml)
  end

  def index_videos(library)
    library['videos'].each_with_object({}) do |video, map|
      map[File.basename(video['path'])] = {
        path: video['path'],
        media_type: video['media_type'] || 'video'
      }
    end
  end

  def build_clips(roughcut, video_index)
    roughcut['clips'].filter_map do |clip|
      source = clip['source_file']
      entry  = video_index[source]

      unless entry
        warn "Warning: Source file not found in library data: #{source}"
        next
      end

      clip_for(clip, entry)
    end
  end

  # Build the generator's clip hash. Video and audio are trimmed with in/out
  # points; a still image has no intrinsic timing, so it gets an explicit
  # on-timeline duration starting at 0. media_type rides along so the generators
  # know which kind of timeline element to emit.
  def clip_for(clip, entry)
    if entry[:media_type] == 'image'
      { path: entry[:path], start_at: 0.0, duration: image_duration_seconds(clip), media_type: 'image' }
    else
      start_at = timecode_to_seconds(clip['in_point'])
      duration = timecode_to_seconds(clip['out_point']) - start_at
      { path: entry[:path], start_at: start_at.to_f, duration: duration.to_f, media_type: entry[:media_type] }
    end
  end

  # An image clip's on-timeline length: an explicit `duration` (HH:MM:SS.ss or a
  # bare number of seconds), else the in/out span if both are given, else the
  # default.
  def image_duration_seconds(clip)
    raw = clip['duration']
    return raw.to_f if raw.is_a?(Numeric)
    return timecode_to_seconds(raw).to_f if raw.is_a?(String) && !raw.strip.empty?

    if clip['in_point'] && clip['out_point']
      span = timecode_to_seconds(clip['out_point']) - timecode_to_seconds(clip['in_point'])
      return span.to_f if span.positive?
    end

    DEFAULT_IMAGE_DURATION_SECONDS
  end

  # Accepts HH:MM:SS or HH:MM:SS.s
  def timecode_to_seconds(timecode)
    hours, minutes, seconds = timecode.split(':')
    hours.to_i * 3600 + minutes.to_i * 60 + seconds.to_f
  end

  def resolve_editor(input)
    editor = input.downcase.to_sym
    return editor if EDITOR_LABELS.key?(editor)

    raise ArgumentError, "Unknown editor '#{input}'. Use 'fcpx', 'premiere', or 'resolve'"
  end

  def write_xml(clips, editor)
    puts "Converting #{clips.length} clips to #{EDITOR_LABELS.fetch(editor)}..."
    ButterCut.new(clips, editor: editor).save(@output_path)
    puts "\n✓ Rough cut exported to: #{@output_path}"
  end

  def validate_fcpxml(xml_path)
    dtd_path = File.expand_path('../../dtd/FCPXMLv1_8.dtd', __dir__)
    return puts "⚠ DTD not found at #{dtd_path}; skipping validation." unless File.exist?(dtd_path)
    return puts '⚠ xmllint not found; skipping validation.' unless system('command -v xmllint > /dev/null 2>&1')

    output = `xmllint --noout --dtdvalid "#{dtd_path}" "#{xml_path}" 2>&1`
    if $?.success?
      puts '✓ FCPXML validates against FCPXMLv1_8.dtd'
    else
      warn '✗ FCPXML failed DTD validation:'
      warn output
      exit 1
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { editor: 'fcpx' }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] <roughcut.yaml> <output.xml>"
    opts.on('-e', '--editor EDITOR', 'fcpx (default), premiere, or resolve') { |v| options[:editor] = v }
    opts.on('-h', '--help', 'Show usage') { puts opts; exit }
  end
  parser.parse!

  if ARGV.length != 2
    warn parser.help
    exit 1
  end

  begin
    Export.perform(roughcut_path: ARGV[0], output_path: ARGV[1], editor: options[:editor])
  rescue ArgumentError, RuntimeError => e
    warn "Error: #{e.message}"
    exit 1
  end
end
