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

require_relative 'media_tools'

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

  # Library-level metadata cleared by `reset_all`, returning a library to its
  # pre-setup, pre-analysis state: the setup choices (language, editor,
  # transcript_refinement) and the analysis-derived context (footage_summary,
  # user_context). Strings go blank; transcript_refinement goes nil ("unset", so
  # setup re-asks rather than assuming off). nil still serializes the key, so the
  # 002 migration sees it as already-present and won't re-default it on `migrate`.
  CLEARED_METADATA = {
    'user_context'          => '',
    'footage_summary'       => '',
    'language'              => '',
    'editor'                => '',
    'transcript_refinement' => nil
  }.freeze

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

  # The basename used everywhere to refer to a clip. Derived from the full
  # `path` and never stored in library.yaml — one owner so reads, lookups, and
  # the `videos` reader all agree on what a clip is called.
  def self.filename_of(video) = File.basename(video['path'].to_s)

  def self.probe_duration(path)
    output = `#{Shellwords.escape(MediaTools.ffprobe)} -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{Shellwords.escape(path)} 2>&1`
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

  # Canonical on-disk path for one clip's artifact in a given field — the single
  # owner of the per-field filename convention (e.g. summary → `summaries/
  # summary_<clip>.md`). Accepts a clip name with or without extension; the
  # extension is stripped before the namer runs, so `field_path('summary',
  # 'P1055017.mov')` and `field_path('summary', 'P1055017')` both resolve to
  # `.../summaries/summary_P1055017.md`.
  def field_path(field, clipname)
    spec = field_spec(field)
    File.join(@library_dir, spec[:subdir], spec[:namer].call(File.basename(clipname, '.*')))
  end

  def add_videos(video_paths)
    records = Array(video_paths).map { |path| self.class.video_record(path) }
    mutate do |library|
      existing = library['videos'].map { |v| v['path'] }
      records.each do |record|
        raise ArgumentError, "video already in library: #{record['path']}" if existing.include?(record['path'])
      end
      library['videos'].concat(records)
    end
    self
  end

  # Mark `video_filenames` complete for one field. Validates each file exists
  # on disk before writing — atomicity is preserved by building the full plan
  # first and only mutating the YAML once every check passes.
  #
  # `announce:` prints a one-line summary (default). JobRunner passes
  # `announce: false` because it owns its own progress output and calls this
  # once per finished job.
  def complete!(field, video_filenames, announce: true)
    field_spec(field) # validate the field name up front
    count = 0
    mutate do |library|
      pairs = Array(video_filenames).map do |filename|
        video = find_video!(library, filename)
        path = field_path(field, filename)
        raise ArgumentError, "#{field} file does not exist: #{path}" unless File.exist?(path)

        [video, File.basename(path)]
      end
      pairs.each { |video, stored_filename| video[field] = stored_filename }
      count = pairs.size
    end
    puts "#{@name}: #{field} set for #{count} #{pluralize(count, 'video')}" if announce
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

  # Destructive: clear library-level metadata back to an unconfigured state —
  # both the setup choices and the analysis-derived context (see
  # CLEARED_METADATA). Video records and dates are kept. Part of `reset_all`'s
  # factory reset, so a re-run starts setup and footage analysis from scratch.
  def reset_metadata!
    mutate { |library| CLEARED_METADATA.each { |key, value| library[key] = value } }
    puts "#{@name}: metadata reset (#{CLEARED_METADATA.keys.join(', ')})"
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

    cleared = 0
    mutate do |library|
      library['videos'].each do |video|
        next unless present?(video['visual_transcript'])

        video['visual_transcript'] = ''
        cleared += 1
      end
    end

    puts format_reset_summary('visual_transcript removed', cleared, swept, errors)
    self
  end

  # Each record carries the stored fields plus a derived `filename` (basename of
  # `path`). The merge returns copies, so the convenience key never reaches the
  # write path — mutations load and persist via `load_library` directly.
  def videos = load_library['videos'].map { |v| v.merge('filename' => self.class.filename_of(v)) }
  def language = load_library['language']
  def transcript_refinement = load_library['transcript_refinement']
  def user_context = load_library['user_context'].to_s
  def footage_summary = load_library['footage_summary'].to_s
  def editor = load_library['editor']

  # Update any subset of the editable metadata fields. Omitted (nil) fields are
  # left alone; pass `''` to clear a string field. `transcript_refinement` takes
  # a real boolean — the CLI coerces "true"/"false" before calling here.
  def update_metadata!(footage_summary: nil, user_context: nil, language: nil, editor: nil, transcript_refinement: nil)
    mutate do |library|
      library['footage_summary'] = footage_summary unless footage_summary.nil?
      library['user_context'] = user_context unless user_context.nil?
      library['language'] = language unless language.nil?
      library['editor'] = editor unless editor.nil?
      library['transcript_refinement'] = transcript_refinement unless transcript_refinement.nil?
    end
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

  # Clips still missing one specific artifact, as records the JobRunner can turn
  # straight into jobs. Unlike `incomplete_videos` (missing ANY field), this is
  # scoped to a single field so the runner can build one independent batch per
  # phase — transcripts and contact sheets don't depend on each other.
  def pending(field)
    field_spec(field) # validate the field name up front
    videos.filter_map { |video| clip_record(video) unless present?(video[field]) }
  end

  # Every clip as a job-ready record, in the same shape as `pending` but
  # unfiltered. FootageProcessor's --force path uses this to rebuild artifacts
  # that already exist; keeping it here means the record shape has one owner.
  def clip_records = videos.map { |video| clip_record(video) }

  # Per-clip artifact status for the live "follow along" view: every clip with a
  # boolean per field (transcript, contact_sheet, summary). Read-only, so it's
  # safe to poll from a separate process (the status server) while the JobRunner
  # records progress — atomic writes keep each read whole.
  def clip_statuses
    videos.map do |video|
      FIELDS.keys.each_with_object('filename' => self.class.filename_of(video)) do |field, row|
        row[field] = present?(video[field])
      end
    end
  end

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

      clip_record(video).merge('missing' => missing)
    end
  end

  # The job-ready shape of one clip: just what a Job constructor (and the
  # JobRunner / status callers) need. Single owner of this hash so `pending`,
  # `clip_records`, and `incomplete_from` stay in lockstep.
  def clip_record(video)
    {
      'filename' => self.class.filename_of(video),
      'path' => video['path'],
      'duration' => video['duration']
    }
  end

  def reset_field!(field)
    spec = field_spec(field)
    dir = File.join(@library_dir, spec[:subdir])
    cleared = 0
    orphans = 0
    errors = []

    mutate do |library|
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
    end

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

  # The one path every library.yaml mutation takes. An exclusive flock on a
  # sidecar lockfile makes the whole read-modify-write atomic ACROSS PROCESSES —
  # the background `process_footage.rb` run recording completions vs. the agent
  # updating footage_summary "as transcripts come in" — so neither clobbers the
  # other's changes. The lock also serializes the JobRunner's own worker threads
  # (each call opens its own fd, so flock contends within a process too), which
  # is why the runner needs no separate write mutex.
  #
  # The block receives the freshly-loaded library hash, mutates it in place, and
  # the persisted result is written atomically on a clean return. A raise inside
  # the block skips the write and still releases the lock. The lockfile is a
  # never-renamed sidecar on purpose: flock follows the inode, and write_library
  # renames a new inode into place, so locking library.yaml itself would strand
  # the lock on the old file. The atomic temp+rename inside still gives lockless
  # readers (status_server, `library.rb pending` polls) a whole file.
  def mutate
    File.open("#{@library_yaml_path}.lock", File::CREAT | File::RDWR, 0o644) do |lock|
      lock.flock(File::LOCK_EX)
      library = load_library
      yield library
      write_library(library)
    end
  end

  # Atomic write: render to a sibling temp file, then rename into place.
  # rename(2) is atomic within a filesystem, so a concurrent reader — e.g. an
  # external `library.rb pending` poll running while a JobRunner records
  # progress — always sees a complete file, the old one or the new one, never a
  # half-written torn read.
  def write_library(library)
    tmp = "#{@library_yaml_path}.tmp.#{Process.pid}"
    File.write(tmp, library.to_yaml)
    File.rename(tmp, @library_yaml_path)
  end

  def find_video!(library, video_filename)
    library['videos'].find { |v| self.class.filename_of(v) == video_filename } ||
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
      <name> pending <field>                          — JSON array of clips still missing one field
      <name> ready                                    — exits 0 if every video is ready for roughcut, 1 otherwise
      <name> field_path <field> <clip>                — canonical path for a clip's artifact (e.g. summary → summaries/summary_<clip>.md)

    Writes:
      <name> add_videos <video_path>...               — append video records
      <name> update_metadata <key> <value...>         — set footage_summary, user_context, language, editor, or transcript_refinement
      <name> complete <field> <files>                 — mark files done for one field
      <name> reset <field> [<field>...]               — wipe one or more phases
      <name> reset_all                                — factory reset: wipe every field (incl. legacy visual_transcripts) + clear metadata (language, editor, transcript_refinement, footage_summary, user_context)
      <name> reset_all_except_audio_transcripts       — wipe everything except audio transcripts
      <name> remove_visual_transcripts                — sweep legacy visual_*.json + clear field

    <field>: transcript | contact_sheet | summary
    <files>: space- and/or comma-separated
    <key>:   footage_summary | user_context | language | editor | transcript_refinement
             (editor: fcpx|premiere|resolve; transcript_refinement: true|false)

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
    when 'pending'
      field, = rest
      raise ArgumentError, 'pending requires <field>' if field.nil?

      puts JSON.pretty_generate(library.pending(field))
    when 'ready'
      exit(library.ready? ? 0 : 1)
    when 'field_path'
      field, clip = rest
      raise ArgumentError, 'field_path requires <field> <clip>' if field.nil? || clip.nil?

      puts library.field_path(field, clip)
    when 'add_videos'
      raise ArgumentError, 'add_videos requires <video_path>...' if rest.empty?

      library.add_videos(rest)
    when 'update_metadata'
      key, *value_parts = rest
      raise ArgumentError, 'update_metadata requires <key> <value>' if key.nil? || value_parts.empty?

      allowed_keys = %w[footage_summary user_context language editor transcript_refinement]
      raise ArgumentError, "unknown metadata key: #{key} (expected #{allowed_keys.join(', ')})" unless allowed_keys.include?(key)

      value = value_parts.join(' ')
      case key
      when 'transcript_refinement'
        value = case value.strip.downcase
                when 'true', 'yes', '1' then true
                when 'false', 'no', '0' then false
                else raise ArgumentError, "transcript_refinement expects true/false, got: #{value}"
                end
      when 'editor'
        raise ArgumentError, "editor expects fcpx, premiere, or resolve, got: #{value}" unless %w[fcpx premiere resolve].include?(value)
      end

      library.update_metadata!(key.to_sym => value)
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
      library.reset_metadata!
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
