#!/usr/bin/env ruby
# Export rough cut YAML to editor XML using ButterCut

require 'date'
require 'optparse'
require 'yaml'
require_relative '../buttercut'
require_relative 'library'

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

  def perform
    roughcut    = load_yaml(@roughcut_path)
    media_paths = index_media_paths(find_library(@roughcut_path))
    clips       = build_clips(roughcut, media_paths)

    write_xml(clips, @editor)
    validate_fcpxml(@output_path) if @editor == :fcpx
    @output_path
  end

  private

  def load_yaml(path)
    raise "Rough cut file not found: #{path}" unless File.exist?(path)

    YAML.load_file(path, permitted_classes: [Date, Time, Symbol])
  end

  def find_library(roughcut_path)
    match = roughcut_path.match(%r{libraries/([^/]+)/cuts})
    raise "Could not extract library name from path: #{roughcut_path}" unless match

    Library.find(match[1])
  end

  # Reading through Library (not raw YAML) inherits its normalization: `media`
  # is always an array, and a legacy `videos:` library fails loudly with the
  # "run migrate" error instead of silently matching zero clips here.
  def index_media_paths(library)
    library.media.each_with_object({}) do |clip, map|
      map[clip['filename']] = clip['path']
    end
  end

  def build_clips(roughcut, media_paths)
    roughcut['clips'].filter_map do |clip|
      source = clip['source_file']
      path   = media_paths[source]

      unless path
        warn "Warning: Source file not found in library data: #{source}"
        next
      end

      start_at = timecode_to_seconds(clip['in_point'])
      duration = timecode_to_seconds(clip['out_point']) - start_at

      # The editor re-derives image-vs-video from the path in build_asset_map, so
      # we don't thread an `image:` flag through here — it would just be a second,
      # ignored source of truth.
      { path: path, start_at: start_at.to_f, duration: duration.to_f }
    end
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
