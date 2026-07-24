#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'json'
require 'open3'
require_relative 'job'
require_relative 'media_tools'
require_relative 'platform'

# Transcribe one clip's audio with WhisperX, then slim the JSON with
# prepare_audio_script.rb. Pure mechanics — the exact commands that used to live
# in the transcribe-audio sub-agent prompt, now in code so every run is
# identical regardless of which model started it.
#
# Transcript *refinement* (fixing misheard proper nouns from library context) is
# deliberately NOT here. That step is judgment, not mechanics, so it stays a
# Claude step that runs after these jobs finish — see analyze-video/SKILL.md.
class TranscribeJob < Job
  def self.field = 'transcript'

  PREPARE_SCRIPT = File.expand_path('prepare_audio_script.rb', __dir__)

  # Where setup installs WhisperX when it isn't on PATH: the ~/.buttercut venv
  # entry point (Scripts/ on Windows, bin/ elsewhere), or the macOS wrapper.
  WHISPERX_FALLBACK_DIRS = [
    File.join(Dir.home, '.buttercut', 'venv', 'Scripts'),
    File.join(Dir.home, '.buttercut', 'venv', 'bin'),
    File.join(Dir.home, '.buttercut')
  ].freeze

  def self.whisperx_command
    Platform.find_tool('whisperx', :path, *WHISPERX_FALLBACK_DIRS) ||
      raise(MediaTools::MissingBinary,
            'whisperx not found on PATH or under ~/.buttercut — run the setup skill to install it')
  end

  def initialize(library_name:, clip:, video_path:, output_dir:, language_code:, whisper_model:)
    super(library_name: library_name, clip: clip)
    @video_path = video_path
    @output_dir = output_dir
    @language_code = language_code
    @whisper_model = whisper_model
  end

  def perform
    if run_whisperx
      prepare_transcript
    end
    self
  end

  private

  NO_SPEECH_MARKER = 'No active speech found in audio'

  # Returns true if whisperx produced a real transcript, false if it rescued a
  # silent clip by writing an empty one. Raises on any other failure.
  def run_whisperx
    # WhisperX decodes audio by running a bare `ffmpeg` from PATH (see
    # whisperx/audio.py load_audio), so the subprocess gets MediaTools'
    # dependencies-first precedence via PATH — without this, installs whose
    # only ffmpeg is the dependencies/ static build can't transcribe. The
    # resolve call is a preflight: no ffmpeg anywhere raises MediaTools'
    # clear error here instead of a cryptic decode failure inside whisperx.
    MediaTools.ffmpeg
    # Keyed off the environment's own spelling: Windows says `Path`, and adding
    # a second `PATH` to the child's environment is a coin flip over which one
    # it reads — losing that flip silently drops the dependencies/ precedence.
    path_key = Platform.path_env_key
    env = { path_key => [MediaTools::DEPENDENCIES_DIR, ENV.fetch(path_key, '')].join(File::PATH_SEPARATOR) }
    output, status = Open3.capture2e(
      env,
      self.class.whisperx_command, @video_path,
      '--language', @language_code,
      '--model', @whisper_model,
      '--compute_type', 'float32',
      '--device', 'cpu',
      '--output_format', 'json',
      '--output_dir', @output_dir
    )
    return true if status.success?

    if output.include?(NO_SPEECH_MARKER)
      rescue_silent_clip
      return false
    end

    raise "whisperx failed for #{clip} (exit #{status.exitstatus})\n#{output.lines.last(15).join}"
  end

  def rescue_silent_clip
    path = File.join(@output_dir, "#{File.basename(@video_path, '.*')}.json")
    FileUtils.mkdir_p(@output_dir)
    File.write(path, JSON.pretty_generate(
      '_note'        => 'no dialogue',
      'segments'     => [],
      'word_segments' => [],
      'video_path'   => @video_path
    ))
  end

  def prepare_transcript
    json = File.join(@output_dir, "#{File.basename(@video_path, '.*')}.json")
    raise "whisperx produced no transcript at #{json}" unless File.exist?(json)

    ok = system('ruby', PREPARE_SCRIPT, json, @video_path)
    raise "prepare_audio_script failed for #{clip}" unless ok
  end
end

# Single source of truth for the WhisperX command. `process_footage.rb` drives
# this class for whole-library work; this CLI handles one-off / outside-a-library
# transcription so the command never gets copied into a skill prompt.
if __FILE__ == $PROGRAM_NAME
  video_path, output_dir, language_code, whisper_model = ARGV
  if [video_path, output_dir, language_code, whisper_model].any? { |arg| arg.to_s.empty? }
    warn 'Usage: ruby transcribe_job.rb <video_path> <output_dir> <language_code> <whisper_model>'
    exit 1
  end

  begin
    TranscribeJob.new(
      library_name: 'standalone', clip: File.basename(video_path),
      video_path: video_path, output_dir: output_dir,
      language_code: language_code, whisper_model: whisper_model
    ).perform
    puts "✓ #{File.basename(video_path)} transcribed → #{File.join(output_dir, "#{File.basename(video_path, '.*')}.json")}"
  rescue StandardError => e
    warn "transcribe_job: #{e.message}"
    exit 1
  end
end
