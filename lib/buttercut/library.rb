#!/usr/bin/env ruby
# frozen_string_literal: true

# `Library` handle for reading and writing library.yaml. See README.md in
# this directory for the Ruby and shell API reference and usage rules.

require 'date'
require 'English'
require 'fileutils'
require 'json'
require 'shellwords'
require 'yaml'

class Library
  LIBRARIES_ROOT = File.expand_path('../../libraries', __dir__)

  # Per-field on-disk layout. `namer` builds the filename from a clipname;
  # `keep` is an optional regex of filenames the orphan-sweep must not delete
  # (transcripts/ is shared with legacy visual_*.json — those stay).
  FIELDS = {
    'transcript'    => { subdir: 'transcripts',    namer: ->(c) { "#{c}.json" },        keep: /\Avisual_/ }.freeze,
    'contact_sheet' => { subdir: 'contact_sheets', namer: ->(c) { "#{c}_full.jpg" } }.freeze,
    'summary'       => { subdir: 'summaries',      namer: ->(c) { "summary_#{c}.md" } }.freeze
  }.freeze

  SUBDIRS = %w[transcripts contact_sheets summaries cuts plans].freeze

  def self.find(library_name) = new(library_name)

  def self.exists?(library_name)
    return false if library_name.to_s.strip.empty?

    dir = File.join(LIBRARIES_ROOT, library_name)
    File.directory?(dir) && File.exist?(File.join(dir, 'library.yaml'))
  end

  def self.list
    return [] unless File.directory?(LIBRARIES_ROOT)

    Dir.children(LIBRARIES_ROOT)
       .filter_map { |name| yaml = File.join(LIBRARIES_ROOT, name, 'library.yaml'); [name, File.mtime(yaml)] if File.exist?(yaml) }
       .sort_by { |_name, mtime| -mtime.to_f }
       .map(&:first)
  end

  # The most recent libraries, ordered by the newest mtime among library.yaml
  # and the known artifact subdirs. Why those and not deep recursion: footage
  # analysis adds/removes files in transcripts/contact_sheets/summaries/cuts/
  # plans/, and a directory's mtime updates on every such add or remove — so
  # one stat per subdir captures activity without a recursive glob. Scales
  # flat with library count regardless of how many files each one holds.
  def self.recent(limit: 10)
    return [] unless File.directory?(LIBRARIES_ROOT)

    Dir.children(LIBRARIES_ROOT)
       .filter_map do |name|
         dir = File.join(LIBRARIES_ROOT, name)
         yaml = File.join(dir, 'library.yaml')
         next unless File.exist?(yaml)

         mtimes = [File.mtime(yaml)]
         SUBDIRS.each do |sub|
           path = File.join(dir, sub)
           mtimes << File.mtime(path) if File.directory?(path)
         end
         [name, mtimes.max]
       end
       .sort_by { |_name, mtime| -mtime.to_f }
       .first(limit)
       .map(&:first)
  end

  def self.create(library_name, language:, editor:, transcript_refinement:, video_paths:)
    raise ArgumentError, 'library_name is required' if library_name.to_s.strip.empty?

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
      'videos' => Array(video_paths).map { |path| video_record(path) }
    }
    File.write(File.join(dir, 'library.yaml'), payload.to_yaml)
    find(library_name)
  end

  def self.video_record(path)
    raise ArgumentError, 'video path is required' if path.to_s.strip.empty?

    expanded = File.expand_path(path)
    raise ArgumentError, "video file not found: #{expanded}" unless File.exist?(expanded)

    {
      'path' => expanded,
      'duration' => probe_duration(expanded),
      'transcript' => '',
      'contact_sheet' => '',
      'summary' => ''
    }
  end

  def self.probe_duration(path)
    output = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{Shellwords.escape(path)} 2>&1`
    raise ArgumentError, "ffprobe failed for #{path}: #{output.strip}" unless $CHILD_STATUS.success?

    Time.at(Float(output.strip).to_i).utc.strftime('%H:%M:%S')
  rescue ArgumentError, TypeError => e
    raise ArgumentError, "ffprobe returned non-numeric duration for #{path}: #{e.message}"
  end

  # Raised by check_for_update! to hand the actual update check to the agent.
  class UpdateCheckNeeded < StandardError; end

  REPO_ROOT = File.expand_path('../..', __dir__)
  UPDATE_CHECK_FILE = 'last_buttercut_update_check' # repo-root mtime stamp; gitignored
  UPDATE_CHECK_INTERVAL = 86_400 # seconds (24h)

  def self.check_for_update!(repo_root: REPO_ROOT)
    stamp = File.join(repo_root, UPDATE_CHECK_FILE)

    # First run on a fresh checkout (clone, update-buttercut rsync, or setup):
    # no stamp yet. The repo is current by definition, so seed the stamp and
    # stay quiet — the first nudge comes a day later, not on the very first command.
    unless File.exist?(stamp)
      record_update_check!(repo_root: repo_root)
      return
    end

    return if (Time.now - File.mtime(stamp)) < UPDATE_CHECK_INTERVAL

    raise UpdateCheckNeeded,
      "it's been over a day since ButterCut last checked for updates. " \
      'Call `git fetch origin main` then `git log --oneline HEAD..origin/main`. ' \
      'If `main` is ahead, use the update-buttercut skill. ' \
      'Then run `ruby lib/buttercut/library.rb update_checked` to record the check ' \
      'and re-run your command.'
  end

  def self.record_update_check!(repo_root: REPO_ROOT)
    FileUtils.touch(File.join(repo_root, UPDATE_CHECK_FILE))
  end

  attr_reader :name

  def initialize(library_name)
    raise ArgumentError, 'library_name is required' if library_name.to_s.strip.empty?

    @name = library_name
    @library_dir = File.join(LIBRARIES_ROOT, library_name)
    raise ArgumentError, "library not found: #{@library_dir}" unless File.directory?(@library_dir)

    @library_yaml_path = File.join(@library_dir, 'library.yaml')
    raise ArgumentError, "library.yaml not found in #{@library_dir}" unless File.exist?(@library_yaml_path)
  end

  def dir = @library_dir

  def field_path(field, clipname)
    spec = field_spec(field)
    File.join(@library_dir, spec[:subdir], spec[:namer].call(clipname))
  end

  def add_videos(video_paths)
    library = load_library
    existing = library['videos'].map { |v| v['path'] }
    records = Array(video_paths).map { |path| self.class.video_record(path) }
    records.each do |record|
      raise ArgumentError, "video already in library: #{record['path']}" if existing.include?(record['path'])
    end

    library['videos'].concat(records)
    write_library(library)
    self
  end

  # Mark `video_filenames` complete for one field. Validates each file exists
  # on disk before writing — atomicity is preserved by building the full plan
  # first and only mutating the YAML once every check passes.
  def complete!(field, video_filenames)
    spec = field_spec(field)
    library = load_library
    pairs = Array(video_filenames).map do |filename|
      video = find_video!(library, filename)
      stored_filename = spec[:namer].call(File.basename(filename, '.*'))
      path = File.join(@library_dir, spec[:subdir], stored_filename)
      raise ArgumentError, "#{field} file does not exist: #{path}" unless File.exist?(path)

      [video, stored_filename]
    end
    pairs.each { |video, stored_filename| video[field] = stored_filename }
    write_library(library)
    puts "#{@name}: #{field} set for #{pairs.size} #{pluralize(pairs.size, 'video')}"
    self
  end

  # Destructive: for each named field, delete every file in its subdir and
  # clear the field on every video. Pass several names to wipe several phases
  # in one call. The transcripts/ sweep leaves `visual_*.json` alone so
  # `remove_visual_transcripts!` stays the explicit tool for legacy cleanup.
  def reset!(*fields)
    fields.each { |f| reset_field!(f) }
    self
  end

  # Delete every `transcripts/visual_*.json` file and clear the
  # `visual_transcript` field on every video. Legacy cleanup for libraries
  # that predate the contact-sheet pipeline.
  def remove_visual_transcripts!
    dir = File.join(@library_dir, 'transcripts')
    swept = 0
    errors = []

    if File.directory?(dir)
      Dir.children(dir).each do |entry|
        next unless entry.start_with?('visual_')
        next unless File.file?(File.join(dir, entry))

        begin
          File.delete(File.join(dir, entry))
          swept += 1
        rescue StandardError => e
          errors << "#{entry}: #{e.message}"
        end
      end
    end

    library = load_library
    cleared = 0
    library['videos'].each do |video|
      next unless present?(video['visual_transcript'])

      video['visual_transcript'] = ''
      cleared += 1
    end
    write_library(library) if cleared.positive?

    puts format_reset_summary('visual_transcript removed', cleared, swept, errors)
    self
  end

  def videos = load_library['videos']
  def language = load_library['language']
  def transcript_refinement = load_library['transcript_refinement']
  def user_context = load_library['user_context'].to_s
  def footage_summary = load_library['footage_summary'].to_s
  def editor = load_library['editor']

  # Update one or both free-text metadata fields. Omitted fields are left
  # alone; pass `''` to clear.
  def update_metadata!(footage_summary: nil, user_context: nil)
    library = load_library
    library['footage_summary'] = footage_summary unless footage_summary.nil?
    library['user_context'] = user_context unless user_context.nil?
    write_library(library)
    self
  end

  # True when every video is ready for roughcut work under either pipeline.
  # Current: transcript + summary. Legacy: visual_transcript + summary.
  # `contact_sheet` is intentionally not required — new libraries always have
  # them, and the roughcut sub-agent can generate sheets on demand for legacy
  # libraries when it needs to "see" a clip.
  #
  # Raises if a legacy `roughcuts/` directory is still present — the cut skill
  # writes to `cuts/`, so building anything before migration would scatter
  # output across both directories. The error names the migration script
  # explicitly so the agent reading the message knows what to run.
  def ready?
    if File.directory?(File.join(@library_dir, 'roughcuts'))
      raise "Library '#{@name}' has a legacy `roughcuts/` directory. " \
            'Run `ruby lib/buttercut/library.rb migrate` to fix, ' \
            'or just rename roughcuts/ to cuts/ manually.'
    end

    vids = videos
    return false if vids.empty?

    vids.all? do |v|
      present?(v['summary']) && (present?(v['transcript']) || present?(v['visual_transcript']))
    end
  end

  def incomplete_videos = incomplete_from(videos)

  # Snapshot for picking up a library: top-level metadata plus a
  # clip-completion breakdown. `incomplete_count == 0` means ready for roughcut.
  def summary
    data = load_library
    vids = data['videos']
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

  def field_spec(field)
    FIELDS.fetch(field.to_s) { raise ArgumentError, "unknown field: #{field.inspect}" }
  end

  def present?(value) = !(value.nil? || value.to_s.strip.empty?)

  def pluralize(count, word) = "#{word}#{'s' unless count == 1}"

  def incomplete_from(vids)
    vids.filter_map do |video|
      missing = FIELDS.keys.reject { |f| present?(video[f]) }
      next if missing.empty?

      {
        'filename' => File.basename(video['path'].to_s),
        'path' => video['path'],
        'duration' => video['duration'],
        'missing' => missing
      }
    end
  end

  def reset_field!(field)
    spec = field_spec(field)
    dir = File.join(@library_dir, spec[:subdir])
    library = load_library
    cleared = 0
    errors = []

    library['videos'].each do |video|
      filename = video[field]
      next unless present?(filename)

      begin
        path = File.join(dir, filename)
        File.delete(path) if File.file?(path)
        video[field] = ''
        cleared += 1
      rescue StandardError => e
        errors << "#{filename}: #{e.message}"
      end
    end

    orphans = sweep_orphans(dir, spec[:keep], errors)
    write_library(library)
    puts format_reset_summary("#{field} reset", cleared, orphans, errors)
  end

  def sweep_orphans(dir, keep, errors)
    return 0 unless File.directory?(dir)

    swept = 0
    Dir.children(dir).each do |entry|
      path = File.join(dir, entry)
      next unless File.file?(path)
      next if keep && keep.match?(entry)

      begin
        File.delete(path)
        swept += 1
      rescue StandardError => e
        errors << "#{entry}: #{e.message}"
      end
    end
    swept
  end

  def format_reset_summary(label, cleared, swept, errors)
    msg = "#{@name}: #{label} (#{cleared} #{pluralize(cleared, 'video')} cleared, #{swept} #{pluralize(swept, 'file')} swept)"
    msg += "; #{errors.size} #{pluralize(errors.size, 'error')}: #{errors.join('; ')}" unless errors.empty?
    msg
  end

  # `videos` is guaranteed to be an array on the returned hash so callers can
  # iterate without defensive `|| []` checks.
  def load_library
    data = YAML.safe_load_file(@library_yaml_path, permitted_classes: [Date, Time])
    data['videos'] ||= []
    data
  end

  def write_library(library) = File.write(@library_yaml_path, library.to_yaml)

  def find_video!(library, video_filename)
    library['videos'].find { |v| File.basename(v['path'].to_s) == video_filename } ||
      raise(ArgumentError, "video not found in library.yaml: #{video_filename}")
  end
end

if __FILE__ == $PROGRAM_NAME
  USAGE = <<~USAGE
    Usage:
      ruby library.rb list                            — every library, newest first (library.yaml mtime)
      ruby library.rb recent [N]                      — N most recent libraries by deepest file mtime (default 10)
      ruby library.rb migrate                         — run all migrations across every library
      ruby library.rb update_checked                  — record that you just checked GitHub for a newer ButterCut
      ruby library.rb <library_name> <action> [args]

    Existence + status (no library load required for `exists`):
      <name> exists                                   — exits 0 if library exists, 1 otherwise
      <name> summary                                  — JSON snapshot
      <name> incomplete_videos                        — JSON array of incomplete clips
      <name> ready                                    — exits 0 if every video is ready for roughcut, 1 otherwise

    Writes:
      <name> add_videos <video_path>...               — append video records
      <name> update_metadata <key> <value...>         — set footage_summary or user_context
      <name> complete <field> <files>                 — mark files done for one field
      <name> reset <field> [<field>...]               — wipe one or more phases
      <name> reset_all                                — wipe every field (incl. legacy visual_transcripts)
      <name> reset_all_except_audio_transcripts       — wipe everything except audio transcripts
      <name> remove_visual_transcripts                — sweep legacy visual_*.json + clear field

    <field>: transcript | contact_sheet | summary
    <files>: space- and/or comma-separated
    <key>:   footage_summary | user_context

    Library.create is not exposed via the CLI (kwarg-heavy). From bash:
      ruby -e "require_relative 'lib/buttercut/library'; \\
        Library.create('my-lib', language: 'en', editor: 'fcpx', \\
                       transcript_refinement: true, video_paths: ['/abs/a.mov'])"
  USAGE

  # Agent records that it just checked for updates (see check_for_update!). Kept
  # ahead of the daily gate below so recording a check is never itself gated.
  if ARGV.first == 'update_checked'
    Library.record_update_check!
    exit 0
  end

  if ARGV.first == 'list'
    puts Library.list
    exit 0
  end

  if ARGV.first == 'recent'
    limit = ARGV[1] ? Integer(ARGV[1]) : 10
    puts Library.recent(limit: limit)
    exit 0
  end

  if ARGV.first == 'migrate' && ARGV.size == 1
    migrate_script = File.expand_path('../../scripts/migrate_all.rb', __dir__)
    repo_root = Library::REPO_ROOT
    exec('ruby', migrate_script, chdir: repo_root)
  end

  library_name, action, *rest = ARGV
  if library_name.to_s.empty? || action.to_s.empty?
    warn USAGE
    exit 1
  end

  if action == 'exists'
    exit(Library.exists?(library_name) ? 0 : 1)
  end

  library = begin
    Library.find(library_name)
  rescue StandardError => e
    warn "library: #{e.message}"
    exit 1
  end

  split_files = ->(args) { args.flat_map { |a| a.split(',').map(&:strip).reject(&:empty?) } }

  begin
    Library.check_for_update!

    case action
    when 'summary'
      puts JSON.pretty_generate(library.summary)
    when 'incomplete_videos'
      puts JSON.pretty_generate(library.incomplete_videos)
    when 'ready'
      exit(library.ready? ? 0 : 1)
    when 'add_videos'
      raise ArgumentError, 'add_videos requires <video_path>...' if rest.empty?

      library.add_videos(rest)
    when 'update_metadata'
      key, *value_parts = rest
      raise ArgumentError, 'update_metadata requires <key> <value>' if key.nil? || value_parts.empty?
      raise ArgumentError, "unknown metadata key: #{key} (expected footage_summary or user_context)" unless %w[footage_summary user_context].include?(key)

      library.update_metadata!(key.to_sym => value_parts.join(' '))
    when 'complete'
      field, *files = rest
      raise ArgumentError, 'complete requires <field> <files>' if field.nil? || files.empty?

      library.complete!(field, split_files.call(files))
    when 'reset'
      raise ArgumentError, 'reset requires <field> [<field>...]' if rest.empty?

      library.reset!(*rest)
    when 'reset_all'
      library.reset!(*Library::FIELDS.keys)
      library.remove_visual_transcripts!
    when 'reset_all_except_audio_transcripts'
      library.reset!('contact_sheet', 'summary')
      library.remove_visual_transcripts!
    when 'remove_visual_transcripts'
      library.remove_visual_transcripts!
    else
      warn "unknown action: #{action}"
      warn USAGE
      exit 1
    end
  rescue StandardError => e
    warn "library: #{e.message}"
    exit 1
  end
end
