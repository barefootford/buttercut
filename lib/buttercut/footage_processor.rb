#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'library'
require_relative 'settings'
require_relative 'job_runner'
require_relative 'transcribe_job'
require_relative 'contact_sheet_job'

# Shared mechanics behind process_footage.rb's two subcommands — `transcripts`
# (#transcribe) and `contact-sheets` (#build_contact_sheets). Each builds one
# flat list of jobs (the clips still missing that artifact) and runs them through
# JobRunner, ~2 at a time, recording each into library.yaml as it lands.
#
# There is no combined "process everything" entry point and no phase/ordering
# logic here: the agent runs the transcripts subcommand to completion, then the
# contact-sheets one. Keeping them apart is what guarantees the slow step
# (whisperx) never overlaps the fast one (ffmpeg) and total concurrency stays at
# the cap, not double it.
#
# Idempotent and resumable: the work list comes from the library's pending state,
# so a crash leaves library.yaml as the ledger and a re-run finishes only what's
# left. Judgment steps — transcript refinement, summaries — are NOT here; they
# stay Claude steps that run after these commands exit.
class FootageProcessor
  # Common language names → ISO 639-1. WhisperX wants the code; library.yaml may
  # store either the name ("English") or the code ("en"). Mapping it here is one
  # more decision moved out of the prompt and into code.
  LANGUAGE_CODES = {
    'english' => 'en', 'spanish' => 'es', 'french' => 'fr', 'german' => 'de',
    'italian' => 'it', 'portuguese' => 'pt', 'dutch' => 'nl', 'japanese' => 'ja',
    'chinese' => 'zh', 'korean' => 'ko', 'russian' => 'ru'
  }.freeze

  def initialize(library_name, jobs: nil, force: false, clips: nil, io: $stdout)
    @library = Library.find(library_name)
    @jobs = jobs # explicit --jobs override; nil → JobRunner reads settings.yaml
    @force = force
    @clips = clips && Array(clips)
    @io = io
    validate_clips!
  end

  # Transcribe every candidate clip with WhisperX. Returns true if all succeeded.
  def transcribe
    code = language_code(@library.language)
    model = settings.whisper_model
    output_dir = File.join(@library.dir, 'transcripts')
    jobs = candidates('transcript').map do |clip|
      TranscribeJob.new(
        library_name: @library.name, clip: clip['filename'],
        video_path: clip['path'], output_dir: output_dir,
        language_code: code, whisper_model: model
      )
    end
    process(jobs, 'transcript')
  end

  # Build a contact sheet for every candidate clip. Returns true if all succeeded.
  def build_contact_sheets
    jobs = candidates('contact_sheet').map do |clip|
      ContactSheetJob.new(
        library_name: @library.name, clip: clip['filename'],
        video_path: clip['path'], duration: clip['duration'], library_dir: @library.dir
      )
    end
    process(jobs, 'contact sheet')
  end

  private

  def settings = @settings ||= Settings.load

  def process(jobs, noun)
    if jobs.empty?
      @io.puts "Nothing to do — every clip already has a #{noun}."
      @io.puts '(Use --force, optionally with --clips, to rebuild ones that already exist.)' unless @force
      return true
    end

    @io.puts "Processing #{noun}s for #{@library.name}: #{jobs.size} clip(s)."
    results = JobRunner.new(@library, concurrency: @jobs, io: @io).run(jobs)
    report_summary(results, noun)
    results.all?(&:ok)
  end

  # Clips to (re)process for one field. Default: only those still missing the
  # artifact. With --force: every clip, so existing artifacts get rebuilt.
  # --clips narrows either set to the named clips.
  def candidates(field)
    records = @force ? @library.clip_records : @library.pending(field)
    return records unless @clips

    records.select { |r| @clips.include?(r['filename']) }
  end

  def validate_clips!
    return unless @clips

    known = @library.media.map { |m| File.basename(m['path'].to_s) }
    unknown = @clips - known
    raise "clip(s) not in library: #{unknown.join(', ')}" unless unknown.empty?
  end

  def report_summary(results, noun)
    @io.puts
    failed = results.reject(&:ok)
    mark = failed.empty? ? '✓' : "✗ #{failed.size} failed"
    @io.puts "#{noun}: #{results.size - failed.size}/#{results.size} #{mark}"
    return if failed.empty?

    @io.puts "\nFailures:"
    failed.each { |r| @io.puts "  #{r.clip}: #{r.error.message}" }
  end

  def language_code(language)
    raw = language.to_s.strip
    return 'en' if raw.empty?
    return raw.downcase if raw.length == 2 # already an ISO code

    LANGUAGE_CODES.fetch(raw.downcase) do
      raise "Unknown language #{language.inspect}. Add it to LANGUAGE_CODES or " \
            'store a 2-letter ISO code as `language` in library.yaml.'
    end
  end
end
