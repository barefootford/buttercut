#!/usr/bin/env ruby
# Export rough cut YAML to editor XML using ButterCut

require 'date'
require 'optparse'
require 'yaml'
require_relative '../buttercut'

class Export
  EDITOR_ALIASES = {
    'fcpx'             => :fcpx,
    'finalcut'         => :fcpx,
    'finalcutpro'      => :fcpx,
    'fcp'              => :fcpx,
    'premiere'         => :fcp7,
    'premierepro'      => :fcp7,
    'adobepremiere'    => :fcp7,
    'resolve'          => :fcp7,
    'davinci'          => :fcp7,
    'davinciresolve'   => :fcp7
  }.freeze

  EDITOR_LABELS = {
    fcpx: 'Final Cut Pro X',
    fcp7: 'Premiere / Resolve (FCP7 XML)'
  }.freeze

  def self.perform(roughcut_path:, output_path:, editor: 'fcpx', **sequence_options)
    new(roughcut_path: roughcut_path, output_path: output_path, editor: editor, **sequence_options).perform
  end

  def initialize(roughcut_path:, output_path:, editor:, sequence_frame_rate: nil,
                 sequence_width: nil, sequence_height: nil, windows_file_paths: false,
                 audio_track: nil, audio_start: nil)
    raise ArgumentError, 'roughcut_path is required' if roughcut_path.nil? || roughcut_path.empty?
    raise ArgumentError, 'output_path is required'   if output_path.nil?   || output_path.empty?
    raise ArgumentError, 'editor is required'        if editor.nil?        || editor.to_s.empty?

    if audio_track && !File.exist?(audio_track)
      raise ArgumentError, "Audio file not found: #{audio_track}"
    end

    @roughcut_path       = roughcut_path
    @output_path         = output_path
    @editor              = resolve_editor(editor.to_s)
    @sequence_frame_rate = sequence_frame_rate
    @sequence_width      = sequence_width
    @sequence_height     = sequence_height
    @windows_file_paths  = windows_file_paths
    @audio_track         = audio_track
    @audio_start         = audio_start
  end

  def perform
    roughcut    = load_yaml(@roughcut_path)
    library     = load_library(@roughcut_path)
    video_paths = index_video_paths(library)
    clips       = build_clips(roughcut, video_paths)

    # audio_start can come from the roughcut YAML (e.g. to skip an intro on a music track).
    @audio_start ||= roughcut['audio_start']

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

  def index_video_paths(library)
    library['videos'].each_with_object({}) do |video, map|
      map[File.basename(video['path'])] = video['path']
    end
  end

  def build_clips(roughcut, video_paths)
    roughcut['clips'].filter_map do |clip|
      source = clip['source_file']
      path   = video_paths[source]

      unless path
        warn "Warning: Source file not found in library data: #{source}"
        next
      end

      start_at = timecode_to_seconds(clip['in_point'])
      duration = timecode_to_seconds(clip['out_point']) - start_at

      clip_hash = { path: path, start_at: start_at.to_f, duration: duration.to_f }
      clip_hash[:speed]    = clip['speed'].to_f    if clip['speed']
      clip_hash[:rotation] = clip['rotation'].to_i if clip['rotation']
      clip_hash
    end
  end

  # Accepts HH:MM:SS or HH:MM:SS.s
  def timecode_to_seconds(timecode)
    hours, minutes, seconds = timecode.split(':')
    hours.to_i * 3600 + minutes.to_i * 60 + seconds.to_f
  end

  def resolve_editor(input)
    EDITOR_ALIASES[input.downcase] ||
      raise(ArgumentError, "Unknown editor '#{input}'. Use 'fcpx', 'premiere', or 'resolve'")
  end

  def write_xml(clips, editor)
    puts "Converting #{clips.length} clips to #{EDITOR_LABELS.fetch(editor)}..."

    bc_options = { editor: editor }
    bc_options[:sequence_frame_rate] = @sequence_frame_rate if @sequence_frame_rate
    bc_options[:sequence_width]      = @sequence_width      if @sequence_width
    bc_options[:sequence_height]     = @sequence_height     if @sequence_height
    bc_options[:windows_file_paths]  = @windows_file_paths
    bc_options[:audio_track]         = @audio_track         if @audio_track
    bc_options[:audio_start]         = @audio_start         if @audio_start

    ButterCut.new(clips, **bc_options).save(@output_path)
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
    opts.on('--sequence-fps FPS', Integer, 'Override sequence frame rate (e.g. 50)') { |v| options[:sequence_frame_rate] = v }
    opts.on('--sequence-width W', Integer, 'Custom sequence width (e.g. 1080 for portrait)') { |v| options[:sequence_width] = v }
    opts.on('--sequence-height H', Integer, 'Custom sequence height (e.g. 1920 for portrait)') { |v| options[:sequence_height] = v }
    opts.on('--windows-file-paths', 'Convert WSL /mnt/<drive>/ paths to Windows paths (Premiere on Windows)') { options[:windows_file_paths] = true }
    opts.on('--audio FILE', 'Add audio/music track to sequence (trimmed to fit)') { |v| options[:audio_track] = v }
    opts.on('-h', '--help', 'Show usage') { puts opts; exit }
  end
  parser.parse!

  if ARGV.length != 2
    warn parser.help
    exit 1
  end

  begin
    Export.perform(roughcut_path: ARGV[0], output_path: ARGV[1], **options)
  rescue ArgumentError, RuntimeError => e
    warn "Error: #{e.message}"
    exit 1
  end
end
