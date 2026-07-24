# Export rough cut YAML to editor XML — single-track (ButterCut core).
# The CLI entrypoint lives in the edition-agnostic shim, lib/buttercut/export.rb.

require 'date'
require 'open3'
require 'yaml'
require_relative '../buttercut'
require_relative 'editors'
require_relative 'library'
require_relative 'media_verifier'
require_relative 'platform'

class Export
  EDITOR_LABELS = {
    fcpx: 'Final Cut Pro X',
    resolve: 'DaVinci Resolve (FCPXML)',
    resolve_legacy: 'DaVinci Resolve (legacy FCP7 XML fallback)',
    premiere: 'Adobe Premiere Pro (FCP7 XML + rotation)'
  }.freeze

  def self.perform(roughcut_path:, output_path:, editor: Editors.default)
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
    roughcut = load_yaml(@roughcut_path)
    library  = load_library(@roughcut_path)
    clips    = build_clips(roughcut, library)

    ensure_cut_media_paths_live!(clips)
    write_xml(clips, @editor, roughcut['timeline'])
    validate_fcpxml(@output_path) if fcpxml_editor?
    @output_path
  end

  private

  def load_yaml(path)
    raise "Rough cut file not found: #{path}" unless File.exist?(path)

    YAML.load_file(path, permitted_classes: [Date, Time, Symbol])
  end

  def load_library(roughcut_path)
    library_yaml = "libraries/#{library_name(roughcut_path)}/library.yaml"
    raise "Library file not found: #{library_yaml}" unless File.exist?(library_yaml)

    load_yaml(library_yaml)
  end

  def library_name(roughcut_path)
    Platform.forward_slashes(roughcut_path)[%r{libraries/([^/]+)/cuts}, 1] ||
      raise("Could not extract library name from path: #{roughcut_path}")
  end

  def ensure_cut_media_paths_live!(clips)
    paths = clips.flat_map { |clip| clip_source_paths(clip) }.uniq
    verifier = MediaVerifier.new(paths)
    return if verifier.ok?

    raise "#{verifier.problem_summary(total: paths.size)} " \
          "Run `ruby lib/buttercut/library.rb #{library_name(@roughcut_path)} verify_media` to see the files, " \
          'then read skills/cut/missing_footage.md and follow it.'
  end

  # The source files one clip def needs on disk — an edition seam like
  # EditorBase#asset_sources: a variant whose clips fan out overrides it.
  def clip_source_paths(clip) = [clip[:path]]

  # The editors whose output is FCPXML and so DTD-validated.
  def fcpxml_editor? = %i[fcpx resolve].include?(@editor)

  def index_media_paths(library)
    library['media'].each_with_object({}) do |media, map|
      map[File.basename(media['path'])] = media['path']
    end
  end

  def build_clips(roughcut, library)
    media_paths = index_media_paths(library)
    roughcut['clips'].filter_map { |clip| build_standard_clip(clip, media_paths) }
  end

  # One cut-YAML clip entry → a generator clip def; nil (after a warning)
  # drops the entry.
  def build_standard_clip(clip, media_paths)
    source = clip['source_file']
    path   = media_paths[source]

    unless path
      warn "Warning: Source file not found in library data: #{source}"
      return nil
    end

    type = Library.media_type_of(path)
    if type.nil?
      warn "Warning: #{source} is outside the supported formats — the editor may import it as missing media. " \
           'See "Supported media formats" in AGENTS.md.'
      type = 'video'
    end

    if type == 'image'
      raise "Image clip '#{source}' is missing a required 'duration:' field." unless clip['duration']

      duration = timecode_to_seconds(clip['duration'])
      { path: path, type: :image, duration: duration.to_f }
    else
      start_at = timecode_to_seconds(clip['in_point'])
      duration = timecode_to_seconds(clip['out_point']) - start_at

      result = { path: path, type: :video, start_at: start_at.to_f, duration: duration.to_f }
      # Silence this clip's audio entirely instead of playing it.
      result[:mute] = true if clip['mute']
      result
    end
  end

  # Accepts HH:MM:SS(.s) or bare numeric seconds.
  def timecode_to_seconds(timecode)
    return timecode.to_f if timecode.is_a?(Numeric)

    hours, minutes, seconds = timecode.split(':')
    return hours.to_f if minutes.nil?

    hours.to_i * 3600 + minutes.to_i * 60 + seconds.to_f
  end

  def resolve_editor(input)
    editor = input.downcase.to_sym
    raise ArgumentError, "Unknown editor '#{input}'. Use 'fcpx', 'premiere', 'resolve', or 'resolve_legacy'" unless
      EDITOR_LABELS.key?(editor)

    # Warn, don't raise: exporting FCPXML on Windows to hand to someone on a
    # Mac is a real thing people do. This only catches the case where the
    # library's editor setting predates the machine it's running on.
    if (reason = Editors.unavailable_reason(editor))
      warn "⚠ #{reason}"
    end

    editor
  end

  def write_xml(clips, editor, timeline)
    puts "Converting #{clips.length} clips to #{EDITOR_LABELS.fetch(editor)}..."
    ButterCut.new(clips, editor: editor, timeline: timeline).save(@output_path)
    puts "\n✓ Rough cut exported to: #{@output_path}"
  end

  def validate_fcpxml(xml_path)
    dtd_path = File.expand_path('../../dtd/FCPXMLv1_12.dtd', __dir__)
    return puts "⚠ DTD not found at #{dtd_path}; skipping validation." unless File.exist?(dtd_path)
    return puts '⚠ xmllint not found; skipping validation.' unless Platform.command_available?('xmllint')

    output, status = Open3.capture2e('xmllint', '--noout', '--dtdvalid', dtd_path, xml_path)
    if status.success?
      puts '✓ FCPXML validates against FCPXMLv1_12.dtd'
    else
      warn '✗ FCPXML failed DTD validation:'
      warn output
      exit 1
    end
  end
end
