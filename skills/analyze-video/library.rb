#!/usr/bin/env ruby
# frozen_string_literal: true

# Handle for a library on disk. `Library.find(name)` loads the YAML and
# returns an instance you can ask to mark artifacts done for one or more
# videos. The handle is the only thing that touches library.yaml — every
# other script in the pipeline goes through it.
#
# Each `complete_*` method validates the entire batch before writing:
# every video must be in library.yaml AND every artifact file must exist
# on disk. If anything is missing, the call raises and the YAML is left
# untouched. Pass a single-element array if you're marking one clip done.
#
# Usage from Ruby:
#   require_relative 'library'
#   lib = Library.find('my-library')
#   lib.complete_transcript!(['DJI_0123.mov'])
#   lib.complete_summary!(batch_filenames)
#
# Assert that every video in the library has a given artifact (raises if
# any file is missing on disk):
#   lib.complete_all_transcripts!
#   lib.complete_all_contact_sheets!
#   lib.complete_all_scripts!
#   lib.complete_all_summaries!
#
# Usage from the shell:
#   ruby library.rb <library_name> summary
#   ruby library.rb <library_name> complete_summary DJI_0123.mov,DJI_0124.mov
#   ruby library.rb <library_name> complete_all_contact_sheets
#
# Status:
#   lib.summary → snapshot hash: top-level metadata + clip-completion breakdown.
#     Call this first when picking up a library.
#
# Paths:
#   lib.dir → absolute path to the library on disk
#   lib.artifact_path(field, clipname) → canonical on-disk path for an artifact
#     (same convention `complete_*!` validates against)

require 'date'
require 'English'
require 'fileutils'
require 'json'
require 'shellwords'
require 'yaml'

class Library
  LIBRARIES_ROOT = File.expand_path('../../libraries', __dir__)

  # Each field maps to [subdir, ->(clipname) { artifact_filename }].
  ARTIFACTS = {
    'transcript' => ['transcripts', ->(c) { "#{c}.json" }],
    'contact_sheet' => ['contact_sheets', ->(c) { "#{c}_full.jpg" }],
    'script' => ['scripts', ->(c) { "script_#{c}.txt" }],
    'summary' => ['summaries', ->(c) { "summary_#{c}.md" }]
  }.freeze

  SUBDIRS = %w[transcripts scripts contact_sheets summaries roughcuts plans].freeze

  def self.find(library_name)
    new(library_name)
  end

  # True when both the library directory and its library.yaml exist on disk.
  def self.exists?(library_name)
    return false if library_name.nil? || library_name.to_s.strip.empty?

    dir = File.join(LIBRARIES_ROOT, library_name)
    File.directory?(dir) && File.exist?(File.join(dir, 'library.yaml'))
  end

  # Every library on disk, sorted by library.yaml mtime (most recently
  # touched first). Returns names — call `find` to get a handle.
  def self.list
    return [] unless File.directory?(LIBRARIES_ROOT)

    entries = Dir.children(LIBRARIES_ROOT).filter_map do |name|
      yaml_path = File.join(LIBRARIES_ROOT, name, 'library.yaml')
      next unless File.exist?(yaml_path)

      [name, File.mtime(yaml_path)]
    end
    entries.sort_by { |_name, mtime| -mtime.to_f }.map(&:first)
  end

  # Create a new library on disk and return a handle. Refuses to overwrite
  # an existing library. `video_paths` is an array of absolute paths to video
  # files; durations are read via ffprobe and artifact fields are initialized
  # to empty strings.
  def self.create(library_name, language:, editor:, transcript_refinement:, video_paths:)
    raise ArgumentError, 'library_name is required' if library_name.nil? || library_name.to_s.strip.empty?
    raise ArgumentError, 'video_paths must be an array' unless video_paths.is_a?(Array)

    dir = File.join(LIBRARIES_ROOT, library_name)
    raise ArgumentError, "library already exists: #{dir}" if File.exist?(dir)

    SUBDIRS.each { |sub| FileUtils.mkdir_p(File.join(dir, sub)) }

    today = Date.today.iso8601
    payload = {
      'library_name' => library_name,
      'created_date' => today,
      'last_updated' => today,
      'language' => language,
      'editor' => editor,
      'transcript_refinement' => transcript_refinement,
      'user_context' => '',
      'footage_summary' => 'No footage analyzed yet.',
      'videos' => video_paths.map { |path| video_record(path) }
    }
    File.write(File.join(dir, 'library.yaml'), payload.to_yaml)
    find(library_name)
  end

  def self.video_record(path)
    raise ArgumentError, 'video path is required' if path.nil? || path.to_s.strip.empty?
    raise ArgumentError, "video file not found: #{path}" unless File.exist?(path)

    {
      'path' => path,
      'duration' => probe_duration(path),
      'transcript' => '',
      'script' => '',
      'contact_sheet' => '',
      'summary' => ''
    }
  end

  # Returns "HH:MM:SS" by shelling out to ffprobe. Raises if ffprobe fails
  # or returns a non-numeric value — better to fail loudly at setup than
  # carry a bogus duration through the pipeline.
  def self.probe_duration(path)
    output = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{Shellwords.escape(path)} 2>&1`
    raise ArgumentError, "ffprobe failed for #{path}: #{output.strip}" unless $CHILD_STATUS.success?

    seconds = Float(output.strip)
    format('%02d:%02d:%02d', seconds.to_i / 3600, (seconds.to_i % 3600) / 60, seconds.to_i % 60)
  rescue ArgumentError, TypeError => e
    raise ArgumentError, "ffprobe returned non-numeric duration for #{path}: #{e.message}"
  end

  attr_reader :name

  def initialize(library_name)
    raise ArgumentError, 'library_name is required' if library_name.nil? || library_name.to_s.strip.empty?

    @name = library_name
    @library_dir = File.join(LIBRARIES_ROOT, library_name)
    raise ArgumentError, "library not found: #{@library_dir}" unless File.directory?(@library_dir)

    @library_yaml_path = File.join(@library_dir, 'library.yaml')
    raise ArgumentError, "library.yaml not found in #{@library_dir}" unless File.exist?(@library_yaml_path)
  end

  # Absolute path to the library on disk.
  def dir
    @library_dir
  end

  # Canonical on-disk path for an artifact, e.g.
  # `lib.artifact_path('summary', 'DJI_0123')` → `<libdir>/summaries/summary_DJI_0123.md`.
  # The same convention `complete_<artifact>!` validates against.
  def artifact_path(field, clipname)
    subdir, namer = ARTIFACTS.fetch(field) { raise ArgumentError, "unknown artifact: #{field.inspect}" }
    File.join(@library_dir, subdir, namer.call(clipname))
  end

  # Append video entries to library.yaml. `video_paths` is an array of
  # absolute paths to video files; durations are read via ffprobe and
  # artifact fields default to empty strings. Raises if any path is already
  # present in the library (no silent dedup).
  def add_videos(video_paths)
    raise ArgumentError, 'video_paths must be an array' unless video_paths.is_a?(Array)
    raise ArgumentError, 'video_paths must not be empty' if video_paths.empty?

    library = load_library
    existing_paths = (library['videos'] || []).map { |v| v['path'] }
    new_records = video_paths.map { |path| self.class.video_record(path) }
    new_records.each do |record|
      raise ArgumentError, "video already in library: #{record['path']}" if existing_paths.include?(record['path'])
    end

    library['videos'] = (library['videos'] || []) + new_records
    write_library(library)
    self
  end

  def complete_transcript!(video_filenames)
    update_field!(video_filenames, 'transcript')
  end

  def complete_contact_sheet!(video_filenames)
    update_field!(video_filenames, 'contact_sheet')
  end

  def complete_script!(video_filenames)
    update_field!(video_filenames, 'script')
  end

  def complete_summary!(video_filenames)
    update_field!(video_filenames, 'summary')
  end

  def complete_all_transcripts!
    update_all!('transcript')
  end

  def complete_all_contact_sheets!
    update_all!('contact_sheet')
  end

  def complete_all_scripts!
    update_all!('script')
  end

  def complete_all_summaries!
    update_all!('summary')
  end

  # Destructive: delete every file in the artifact's directory (except legacy
  # `visual_*.json` files in transcripts/) and clear the field on every video
  # in library.yaml. Use to wipe a phase before reprocessing from scratch.
  def reset_transcripts!
    reset!('transcript')
  end

  def reset_contact_sheets!
    reset!('contact_sheet')
  end

  def reset_scripts!
    reset!('script')
  end

  def reset_summaries!
    reset!('summary')
  end

  # Every video entry from library.yaml, in order. Returns the raw hashes —
  # caller can read `path`, `duration`, `transcript`, etc.
  def videos
    load_library['videos'] || []
  end

  # Top-level library metadata. Readers return `nil` (or `false` for
  # `transcript_refinement`) if the field is absent — callers should run
  # migrations first if they need a guaranteed value.
  def language
    load_library['language']
  end

  def transcript_refinement
    load_library['transcript_refinement']
  end

  def user_context
    load_library['user_context'].to_s
  end

  def footage_summary
    load_library['footage_summary'].to_s
  end

  def editor
    load_library['editor']
  end

  # Update one or both of the free-text metadata fields. Pass only what you
  # want to change; omitted fields are left untouched. Pass `''` to clear.
  def update_metadata!(footage_summary: nil, user_context: nil)
    library = load_library
    library['footage_summary'] = footage_summary unless footage_summary.nil?
    library['user_context'] = user_context unless user_context.nil?
    write_library(library)
    self
  end

  # True when every video has been processed under either the legacy or the
  # current pipeline. Legacy: visual_transcript + summary. Current: script +
  # summary. Callers that need stricter readiness (e.g. roughcut, which also
  # wants transcript + contact_sheet) should check those fields directly.
  def processed?
    vids = videos
    return false if vids.empty?

    vids.all? do |video|
      (present?(video['visual_transcript']) && present?(video['summary'])) ||
        (present?(video['script']) && present?(video['summary']))
    end
  end

  # Videos that still need at least one artifact. Each entry is a hash with
  # `filename`, `path`, `duration`, and `missing` (array of artifact field
  # names). An empty array means the library is fully processed.
  #
  # Note: this checks the four current fields only — a legacy clip with
  # visual_transcript + summary will be reported as missing contact_sheet and
  # script. Use `processed?` if you need legacy-aware completeness.
  def incomplete_videos
    incomplete_from(videos)
  end

  # Snapshot of a library's state — top-level metadata plus a clip-completion
  # breakdown. Call this first when picking up a library; the agent gets the
  # narrative context (footage_summary, user_context) and the readiness numbers
  # (video_count, incomplete_count, incomplete clips) in one read. When
  # `incomplete_count` is 0, the library is ready for a roughcut.
  def summary
    data = load_library
    vids = data['videos'] || []
    incomplete = incomplete_from(vids)

    {
      'name' => @name,
      'created_date' => data['created_date'],
      'last_updated' => data['last_updated'],
      'language' => data['language'],
      'editor' => data['editor'],
      'transcript_refinement' => data['transcript_refinement'],
      'user_context' => data['user_context'].to_s,
      'footage_summary' => data['footage_summary'].to_s,
      'video_count' => vids.size,
      'complete_count' => vids.size - incomplete.size,
      'incomplete_count' => incomplete.size,
      'incomplete' => incomplete
    }
  end

  private

  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end

  def incomplete_from(vids)
    vids.filter_map do |video|
      missing = ARTIFACTS.keys.reject { |f| present?(video[f]) }
      next if missing.empty?

      {
        'filename' => File.basename(video['path'].to_s),
        'path' => video['path'],
        'duration' => video['duration'],
        'missing' => missing
      }
    end
  end

  # Disk and YAML stay paired: clearing a video's field only happens after its
  # referenced file is gone. A second pass sweeps orphan files (e.g. chunk
  # contact sheets, or files written when the YAML update failed). Per-item
  # rescues keep one bad file from aborting the rest of the batch.
  def reset!(field)
    subdir, = ARTIFACTS.fetch(field)
    dir = File.join(@library_dir, subdir)
    library = load_library
    cleared = 0
    errors = []

    (library['videos'] || []).each do |video|
      filename = video[field]
      next unless present?(filename)

      path = File.join(dir, filename)
      begin
        File.delete(path) if File.file?(path)
        video[field] = ''
        cleared += 1
      rescue StandardError => e
        errors << "#{filename}: #{e.message}"
      end
    end

    orphans = sweep_orphans(dir, field, errors)
    write_library(library)

    summary = "#{@name}: #{field} reset (#{cleared} video#{'s' unless cleared == 1} cleared, #{orphans} orphan file#{'s' unless orphans == 1} swept)"
    summary += "; #{errors.size} error#{'s' unless errors.size == 1}: #{errors.join('; ')}" unless errors.empty?
    puts summary
    self
  end

  def sweep_orphans(dir, field, errors)
    return 0 unless File.directory?(dir)

    swept = 0
    Dir.children(dir).each do |entry|
      next if field == 'transcript' && entry.start_with?('visual_')

      path = File.join(dir, entry)
      next unless File.file?(path)

      begin
        File.delete(path)
        swept += 1
      rescue StandardError => e
        errors << "#{entry}: #{e.message}"
      end
    end
    swept
  end

  def update_field!(video_filenames, field)
    raise ArgumentError, 'video_filenames must be an array' unless video_filenames.is_a?(Array)
    raise ArgumentError, 'video_filenames must not be empty' if video_filenames.empty?

    apply!(video_filenames, field)
    self
  end

  def update_all!(field)
    library = load_library
    video_filenames = (library['videos'] || []).map { |v| File.basename(v['path'].to_s) }
    raise ArgumentError, "library #{@name} has no videos" if video_filenames.empty?

    apply!(video_filenames, field, library: library)
    self
  end

  def apply!(video_filenames, field, library: nil)
    library ||= load_library
    plan = build_plan!(library, video_filenames, field)
    plan.each { |video, _, filename| video[field] = filename }
    write_library(library)
    puts "#{@name}: #{field} set for #{plan.size} video#{'s' unless plan.size == 1}"
  end

  def build_plan!(library, video_filenames, field)
    subdir, namer = ARTIFACTS.fetch(field)
    video_filenames.map do |video_filename|
      video = find_video!(library, video_filename)
      clipname = File.basename(video_filename, '.*')
      artifact_filename = namer.call(clipname)
      path = File.join(@library_dir, subdir, artifact_filename)
      raise ArgumentError, "#{field} file does not exist: #{path}" unless File.exist?(path)

      [video, video_filename, artifact_filename]
    end
  end

  def load_library
    YAML.safe_load_file(@library_yaml_path, permitted_classes: [Date, Time])
  end

  def write_library(library)
    File.write(@library_yaml_path, library.to_yaml)
  end

  def find_video!(library, video_filename)
    videos = library['videos'] || []
    match = videos.find { |v| File.basename(v['path'].to_s) == video_filename }
    return match if match

    raise ArgumentError, "video not found in library.yaml: #{video_filename}"
  end
end

if __FILE__ == $PROGRAM_NAME
  library_name = ARGV[0]
  action = ARGV[1]
  filename_args = ARGV[2..] || []

  if library_name.nil? || library_name.empty? || action.nil? || action.empty?
    warn 'Usage: ruby library.rb <library_name> <action> [video_filenames...]'
    warn '  read-only actions (no <video_filenames>):'
    warn '    summary                  — JSON snapshot: top-level metadata + clip-completion breakdown'
    warn '    incomplete_videos        — JSON array of videos missing any artifact'
    warn '    processed                — exits 0 if every video is processed, 1 otherwise'
    warn '  per-batch actions (require <video_filenames>):'
    warn '    complete_transcript, complete_contact_sheet, complete_script, complete_summary'
    warn '  whole-library actions (no <video_filenames>):'
    warn '    complete_all_transcripts, complete_all_contact_sheets, complete_all_scripts, complete_all_summaries'
    warn '  destructive reset actions (no <video_filenames>):'
    warn '    reset_transcripts, reset_contact_sheets, reset_scripts, reset_summaries'
    warn '  <video_filenames>: space- and/or comma-separated (DJI_0123.mov DJI_0124.mov OR DJI_0123.mov,DJI_0124.mov)'
    exit 1
  end

  takes_filenames = action.start_with?('complete_') && !action.start_with?('complete_all_')
  if !takes_filenames && filename_args.any?
    warn "action #{action} does not take filename arguments (got: #{filename_args.join(' ')})"
    exit 1
  end
  if takes_filenames && filename_args.empty?
    warn "action #{action} requires <video_filenames>"
    exit 1
  end

  library = begin
    Library.find(library_name)
  rescue StandardError => e
    warn "library: #{e.message}"
    exit 1
  end

  begin
    case action
    when 'summary'
      puts JSON.pretty_generate(library.summary)
    when 'incomplete_videos'
      puts JSON.pretty_generate(library.incomplete_videos)
    when 'processed'
      exit(library.processed? ? 0 : 1)
    when /\A(reset_|complete_all_|complete_)/
      method_name = "#{action}!"
      unless library.respond_to?(method_name)
        warn "unknown action: #{action}"
        exit 1
      end
      if takes_filenames
        video_filenames = filename_args.flat_map { |a| a.split(',').map(&:strip).reject(&:empty?) }
        library.public_send(method_name, video_filenames)
      else
        library.public_send(method_name)
      end
    else
      warn "unknown action: #{action}"
      exit 1
    end
  rescue StandardError => e
    warn "library: #{e.message}"
    exit 1
  end
end
