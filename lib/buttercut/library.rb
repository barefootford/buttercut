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
require_relative 'version'

class Library
  LIBRARIES_ROOT = File.expand_path('../../libraries', __dir__)

  # Per-field on-disk layout. `namer` builds the filename from a clip key
  # (see `clip_key`); `keep` is an optional regex of filenames the
  # orphan-sweep must not delete (transcripts/ is shared with legacy
  # visual_*.json — those stay).
  FIELDS = {
    'transcript'    => { subdir: 'transcripts',    namer: ->(c) { "#{c}.json" },        keep: /\Avisual_/ }.freeze,
    'contact_sheet' => { subdir: 'contact_sheets', namer: ->(c) { "#{c}_full.jpg" } }.freeze,
    'summary'       => { subdir: 'summaries',      namer: ->(c) { "summary_#{c}.md" } }.freeze
  }.freeze

  # What kinds of media a library holds, keyed by file extension. `fields`
  # names the FIELDS entries that apply to the type (everything else —
  # ready?, pending, incomplete, complete!, reset — is driven from here, so
  # a new type is one registry entry, not a code audit). `extensions` is a
  # closed allowlist enforced when ADDING media; the video set is the Venn
  # intersection of containers Final Cut, Premiere, and Resolve all import
  # natively (see "Supported media formats" in AGENTS.md). Reads stay
  # lenient: an already-present entry with an unrecognized extension is
  # treated as video (`unsupported_media` surfaces those for cleanup).
  #
  # ButterCut Pro extends this registry (e.g. an 'audio' entry) in its fork;
  # entries are matched in order, so additions are checked before anything
  # else rejects.
  MEDIA_TYPES = {
    'video' => { fields: %w[transcript contact_sheet summary], probe_duration: true,
                 extensions: %w[mov mp4 mts m2ts mxf avi] }.freeze,
    'image' => { fields: %w[summary], probe_duration: false,
                 extensions: %w[jpg jpeg png] }.freeze
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

  def self.create(library_name, language:, editor:, transcript_refinement:, media_paths:)
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
      'media' => Array(media_paths).map { |path| media_record(path) }
    }
    File.write(File.join(dir, 'library.yaml'), payload.to_yaml)
    find(library_name)
  end

  # The media type a path holds, inferred from its extension (never stored in
  # library.yaml — like `filename`, it's fully determined by `path`, so storing
  # it would only create a drift-able duplicate). Returns nil for extensions
  # outside every registry set; callers decide whether that's a rejection
  # (adding) or a video fallback (reading what's already in the yaml).
  def self.media_type_of(path)
    ext = File.extname(path.to_s).delete_prefix('.').downcase
    MEDIA_TYPES.each { |type, spec| return type if spec[:extensions].include?(ext) }
    nil
  end

  def self.fields_for(type)
    MEDIA_TYPES.fetch(type) { raise ArgumentError, "unknown media type: #{type.inspect}" }[:fields]
  end

  def self.media_record(path)
    raise ArgumentError, 'media path is required' if path.to_s.strip.empty?

    expanded = File.expand_path(path)
    raise ArgumentError, "media file not found: #{expanded}" unless File.exist?(expanded)

    type = media_type_of(expanded)
    raise ArgumentError, unsupported_format_message(expanded) if type.nil?

    spec = MEDIA_TYPES[type]
    record = { 'path' => expanded }
    record['duration'] = probe_duration(expanded) if spec[:probe_duration]
    spec[:fields].each { |field| record[field] = '' }
    record
  end

  def self.unsupported_format_message(path)
    sets = MEDIA_TYPES.map { |type, spec| "#{type}: #{spec[:extensions].join(', ')}" }.join('; ')
    "unsupported media format for #{File.basename(path)}. Supported extensions — #{sets}. " \
      'ffmpeg can convert it to a supported format — see "Supported media formats" in AGENTS.md.'
  end

  # The basename used everywhere to refer to a clip. Derived from the full
  # `path` and never stored in library.yaml — one owner so reads, lookups, and
  # the `media` reader all agree on what a clip is called.
  def self.filename_of(media) = File.basename(media['path'].to_s)

  # The key artifact filenames are built from. Videos keep the original
  # convention (extension stripped, matching every existing artifact on disk).
  # Images flatten the extension in (DJI_0123.jpg → DJI_0123_jpg) so a photo
  # and a video sharing a basename — common with drones and mirrorless stills —
  # can't collide on artifact names.
  def self.clip_key(filename)
    base = File.basename(filename.to_s, '.*')
    return base unless media_type_of(filename) == 'image'

    "#{base}_#{File.extname(filename.to_s).delete_prefix('.').downcase}"
  end

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
      'Call `GIT_TERMINAL_PROMPT=0 git fetch origin main` then `git log --oneline HEAD..origin/main`. ' \
      'If `main` is ahead, use the update-buttercut skill; if the fetch fails, ' \
      'follow the failure guidance in that skill. ' \
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
  # summary_<clip>.md`). For videos the extension is stripped before the namer
  # runs, so `field_path('summary', 'P1055017.mov')` and `field_path('summary',
  # 'P1055017')` both resolve to `.../summaries/summary_P1055017.md`. Image
  # clipnames must include their extension — it's part of the clip key
  # (`summary_DJI_0123_jpg.md`).
  def field_path(field, clipname)
    spec = field_spec(field)
    File.join(@library_dir, spec[:subdir], spec[:namer].call(self.class.clip_key(clipname)))
  end

  def add_media(media_paths)
    records = Array(media_paths).map { |path| self.class.media_record(path) }
    mutate do |library|
      existing = library['media'].map { |m| m['path'] }
      records.each do |record|
        raise ArgumentError, "media already in library: #{record['path']}" if existing.include?(record['path'])
      end
      library['media'].concat(records)
    end
    self
  end

  # Remove entries from library.yaml and delete their artifact files
  # (transcripts, contact sheets, summaries — plus legacy visual transcripts).
  # NEVER touches the source footage itself.
  def remove_media!(media_filenames)
    removed = []
    mutate do |library|
      Array(media_filenames).each do |filename|
        media = find_media!(library, filename)
        delete_artifacts(media)
        library['media'].delete(media)
        removed << filename
      end
    end
    puts "#{@name}: removed #{removed.size} media #{removed.size == 1 ? 'entry' : 'entries'} " \
         "(#{removed.join(', ')}) — source files untouched"
    self
  end

  # Entries whose extension is outside every registry set — footage that snuck
  # in before the allowlist existed. Reads stay lenient (these are treated as
  # video), but they'd export into XML the editors can't import, so skills
  # surface them for convert-and-swap or removal.
  def unsupported_media
    load_library['media'].filter_map do |media|
      next if self.class.media_type_of(media['path'])

      {
        'filename' => self.class.filename_of(media),
        'path' => media['path'],
        'extension' => File.extname(media['path'].to_s).delete_prefix('.').downcase
      }
    end
  end

  # Mark `media_filenames` complete for one field. Validates each file exists
  # on disk before writing — atomicity is preserved by building the full plan
  # first and only mutating the YAML once every check passes.
  #
  # `announce:` prints a one-line summary (default). JobRunner passes
  # `announce: false` because it owns its own progress output and calls this
  # once per finished job.
  def complete!(field, media_filenames, announce: true)
    field_spec(field) # validate the field name up front
    count = 0
    mutate do |library|
      pairs = Array(media_filenames).map do |filename|
        media = find_media!(library, filename)
        type = self.class.media_type_of(media['path']) || 'video'
        unless self.class.fields_for(type).include?(field.to_s)
          raise ArgumentError, "#{field} does not apply to #{type} media: #{filename}"
        end

        path = field_path(field, filename)
        raise ArgumentError, "#{field} file does not exist: #{path}" unless File.exist?(path)

        [media, File.basename(path)]
      end
      pairs.each { |media, stored_filename| media[field] = stored_filename }
      count = pairs.size
    end
    puts "#{@name}: #{field} set for #{count} #{pluralize(count, 'clip')}" if announce
    self
  end

  # Destructive: for each named field, delete every file in its subdir and
  # clear the field on every media entry that has it. Pass several names to
  # wipe several phases in one call. The transcripts/ sweep leaves
  # `visual_*.json` alone so `remove_visual_transcripts!` stays the explicit
  # tool for legacy cleanup.
  def reset!(*fields)
    fields.each { |f| reset_field!(f) }
    self
  end

  # Destructive: clear library-level metadata back to an unconfigured state —
  # both the setup choices and the analysis-derived context (see
  # CLEARED_METADATA). Media records and dates are kept. Part of `reset_all`'s
  # factory reset, so a re-run starts setup and footage analysis from scratch.
  def reset_metadata!
    mutate { |library| CLEARED_METADATA.each { |key, value| library[key] = value } }
    puts "#{@name}: metadata reset (#{CLEARED_METADATA.keys.join(', ')})"
    self
  end

  # Delete every `transcripts/visual_*.json` file and clear the
  # `visual_transcript` field on every entry. Legacy cleanup for libraries
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
      library['media'].each do |media|
        next unless present?(media['visual_transcript'])

        media['visual_transcript'] = ''
        cleared += 1
      end
    end

    puts format_reset_summary('visual_transcript removed', cleared, swept, errors)
    self
  end

  # Each record carries the stored fields plus two derived keys: `filename`
  # (basename of `path`) and `type` (inferred from the extension; unknown
  # extensions already in the yaml read as video). The merge returns copies,
  # so the convenience keys never reach the write path — mutations load and
  # persist via `load_library` directly.
  def media = merged_media(load_library)
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

  # True when every media entry is ready for roughcut work. Videos under
  # either pipeline — current: transcript + summary; legacy: visual_transcript
  # + summary. `contact_sheet` is intentionally not required — new libraries
  # always have them, and the roughcut sub-agent can generate sheets on demand
  # for legacy libraries when it needs to "see" a clip. Other types just need
  # their registry fields (image: summary).
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

    meds = media
    return false if meds.empty?

    meds.all? { |m| artifacts_ready?(m) }
  end

  def incomplete_media = incomplete_from(media)

  # Clips still missing one specific artifact, as records the JobRunner can turn
  # straight into jobs. Unlike `incomplete_media` (missing ANY applicable
  # field), this is scoped to a single field so the runner can build one
  # independent batch per phase — transcripts and contact sheets don't depend
  # on each other. Only types the field applies to are returned, so the
  # WhisperX/ffmpeg pipeline never sees images.
  def pending(field)
    field_spec(field) # validate the field name up front
    media.filter_map do |m|
      next unless self.class.fields_for(m['type']).include?(field.to_s)

      clip_record(m) unless present?(m[field])
    end
  end

  # Every clip as a job-ready record, in the same shape as `pending` but
  # unfiltered. FootageProcessor's --force path uses this to rebuild artifacts
  # that already exist; keeping it here means the record shape has one owner.
  def clip_records = media.map { |m| clip_record(m) }

  # Per-clip artifact status for the live "follow along" view: every clip with
  # a boolean per applicable field. Read-only, so it's safe to poll from a
  # separate process (the status server) while the JobRunner records progress —
  # atomic writes keep each read whole.
  def clip_statuses
    media.map do |m|
      base = { 'filename' => m['filename'], 'type' => m['type'] }
      self.class.fields_for(m['type']).each_with_object(base) do |field, row|
        row[field] = present?(m[field])
      end
    end
  end

  # Snapshot for picking up a library: top-level metadata plus a
  # clip-completion breakdown. `incomplete_count == 0` means ready for roughcut.
  def summary
    data = load_library
    meds = merged_media(data)
    incomplete = incomplete_from(meds)
    counts = meds.group_by { |m| m['type'] }.transform_values(&:size)

    snapshot = {
      'name' => @name,
      'created_date' => data['created_date'],
      'last_updated' => data['last_updated'],
      'language' => data['language'],
      'editor' => data['editor'],
      'transcript_refinement' => data['transcript_refinement'],
      'user_context' => data['user_context'].to_s,
      'footage_summary' => data['footage_summary'].to_s,
      'media_count' => meds.size
    }
    MEDIA_TYPES.each_key { |type| snapshot["#{type}_count"] = counts.fetch(type, 0) }
    snapshot.merge(
      'complete_count' => meds.size - incomplete.size,
      'incomplete_count' => incomplete.size,
      'incomplete' => incomplete
    )
  end

  private

  def field_spec(field)
    FIELDS.fetch(field.to_s) { raise ArgumentError, "unknown field: #{field.inspect}" }
  end

  def present?(value) = !(value.nil? || value.to_s.strip.empty?)

  def pluralize(count, word) = "#{word}#{'s' unless count == 1}"

  def merged_media(data)
    data['media'].map do |m|
      m.merge('filename' => self.class.filename_of(m),
              'type' => self.class.media_type_of(m['path']) || 'video')
    end
  end

  # Legacy-aware per-entry readiness; see `ready?` for the video rule.
  def artifacts_ready?(media)
    if media['type'] == 'video'
      return present?(media['summary']) && (present?(media['transcript']) || present?(media['visual_transcript']))
    end

    self.class.fields_for(media['type']).all? { |f| present?(media[f]) }
  end

  # Expects merged records (with derived `type`).
  def incomplete_from(meds)
    meds.filter_map do |m|
      missing = self.class.fields_for(m['type']).reject { |f| present?(m[f]) }
      next if missing.empty?

      clip_record(m).merge('missing' => missing)
    end
  end

  # The job-ready shape of one clip: just what a Job constructor (and the
  # JobRunner / status callers) need. Single owner of this hash so `pending`,
  # `clip_records`, and `incomplete_from` stay in lockstep. Expects merged
  # records; `duration` is only present for types that probe it.
  def clip_record(media)
    record = {
      'filename' => media['filename'],
      'path' => media['path'],
      'type' => media['type']
    }
    record['duration'] = media['duration'] if media.key?('duration')
    record
  end

  def reset_field!(field)
    spec = field_spec(field)
    dir = File.join(@library_dir, spec[:subdir])
    cleared = 0
    orphans = 0
    errors = []

    mutate do |library|
      library['media'].each do |media|
        filename = media[field]
        next unless present?(filename)

        begin
          path = File.join(dir, filename)
          File.delete(path) if File.file?(path)
          media[field] = ''
          cleared += 1
        rescue StandardError => e
          errors << "#{filename}: #{e.message}"
        end
      end

      orphans = sweep_orphans(dir, spec[:keep], errors)
    end

    puts format_reset_summary("#{field} reset", cleared, orphans, errors)
  end

  # Delete one entry's artifact files on disk (used by remove_media!). Covers
  # every FIELDS artifact the entry has recorded, plus a legacy visual
  # transcript if present. Never touches the source footage.
  def delete_artifacts(media)
    FIELDS.each do |field, spec|
      stored = media[field]
      next unless present?(stored)

      path = File.join(@library_dir, spec[:subdir], stored)
      File.delete(path) if File.file?(path)
    end

    visual = media['visual_transcript']
    return unless present?(visual)

    path = File.join(@library_dir, 'transcripts', visual)
    File.delete(path) if File.file?(path)
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
    msg = "#{@name}: #{label} (#{cleared} #{pluralize(cleared, 'clip')} cleared, #{swept} #{pluralize(swept, 'file')} swept)"
    msg += "; #{errors.size} #{pluralize(errors.size, 'error')}: #{errors.join('; ')}" unless errors.empty?
    msg
  end

  # `media` is guaranteed to be an array on the returned hash so callers can
  # iterate without defensive `|| []` checks. A legacy `videos:` key means the
  # library predates the media schema — refuse to operate until the (pure
  # key-rename) migration has run, same pattern as the roughcuts/ check.
  def load_library
    data = YAML.safe_load_file(@library_yaml_path, permitted_classes: [Date, Time])
    if data.key?('videos') && !data.key?('media')
      raise "Library '#{@name}' uses the legacy `videos:` key. " \
            'Run `ruby lib/buttercut/library.rb migrate` to rename it to `media:` ' \
            '(or rename the key manually — that is the whole migration).'
    end
    data['media'] ||= []
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

  def find_media!(library, media_filename)
    library['media'].find { |m| self.class.filename_of(m) == media_filename } ||
      raise(ArgumentError, "media not found in library.yaml: #{media_filename}")
  end
end

if __FILE__ == $PROGRAM_NAME
  USAGE = <<~USAGE
    Usage:
      ruby library.rb list                            — every library, newest first (library.yaml mtime)
      ruby library.rb recent [N]                      — N most recent libraries by deepest file mtime (default 10)
      ruby library.rb migrate                         — run all migrations across every library
      ruby library.rb update_checked                  — record that you just checked for a newer ButterCut
      ruby library.rb edition                         — print which ButterCut edition this is (core or pro)
      ruby library.rb <library_name> <action> [args]

    Existence + status (no library load required for `exists`):
      <name> exists                                   — exits 0 if library exists, 1 otherwise
      <name> summary                                  — JSON snapshot (media_count + per-type counts + incomplete breakdown)
      <name> incomplete_media                         — JSON array of incomplete clips
      <name> unsupported_media                        — JSON array of entries whose extension no editor imports natively
      <name> pending <field>                          — JSON array of clips still missing one field (only types the field applies to)
      <name> ready                                    — exits 0 if every clip is ready for roughcut, 1 otherwise
      <name> field_path <field> <clip>                — canonical path for a clip's artifact (e.g. summary → summaries/summary_<clip>.md)

    Writes:
      <name> add_media <path>...                      — append media records (type inferred from extension; video: #{Library::MEDIA_TYPES['video'][:extensions].join('/')}; image: #{Library::MEDIA_TYPES['image'][:extensions].join('/')})
      <name> remove_media <files>                     — drop entries + delete their artifacts (source footage untouched)
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
                       transcript_refinement: true, media_paths: ['/abs/a.mov', '/abs/b.jpg'])"
  USAGE

  # Agent records that it just checked for updates (see check_for_update!). Kept
  # ahead of the daily gate below so recording a check is never itself gated.
  if ARGV.first == 'update_checked'
    Library.record_update_check!
    exit 0
  end

  # Which edition this install is (:core open source, :pro). The update skill
  # branches on this; like update_checked it must never hit the daily gate.
  if ARGV.first == 'edition'
    puts ButterCut::EDITION
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
    when 'incomplete_media'
      puts JSON.pretty_generate(library.incomplete_media)
    when 'unsupported_media'
      puts JSON.pretty_generate(library.unsupported_media)
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
    when 'add_media'
      raise ArgumentError, 'add_media requires <path>...' if rest.empty?

      library.add_media(rest)
    when 'remove_media'
      raise ArgumentError, 'remove_media requires <files>' if rest.empty?

      library.remove_media!(split_files.call(rest))
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
