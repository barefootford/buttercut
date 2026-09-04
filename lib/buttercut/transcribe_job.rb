#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'json'
require 'open3'
require_relative 'job'
require_relative 'media_tools'

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
  LOAD_AUDIO_MARKER = 'Failed to load audio'
  PYTHON_TRACEBACK_MARKER = 'Traceback (most recent call last)'

  # The outcome is read from the evidence — the output file and whisperx's
  # own messages — before the exit status. The wrapper script older installs
  # run whisperx through reports 0 for everything (see MediaTools.whisperx),
  # so a status of 0 proves nothing on its own.
  #
  # Returns true if whisperx produced a transcript with dialogue in it, false
  # if the clip is silent and got the empty no-dialogue transcript instead.
  # Raises on any other failure.
  #
  # Silence comes in two shapes, and both end up as the same file on disk:
  #   * no audio stream at all — picture-only drone and action-cam bodies,
  #     screen captures. Caught up front with ffprobe so whisperx never runs;
  #     the ffmpeg decode inside it would only fail.
  #   * an audio stream with no speech — B-roll, ambient, a drone with a mic.
  #     whisperx 3.8+ logs NO_SPEECH_MARKER and exits 0 with an empty-segments
  #     JSON; older versions logged it and exited non-zero without writing
  #     anything. Both are rescued here.
  def run_whisperx
    FileUtils.mkdir_p(@output_dir)
    unless MediaTools.audio_stream?(@video_path)
      rescue_silent_clip
      return false
    end

    # WhisperX decodes audio by running a bare `ffmpeg` from PATH (see
    # whisperx/audio.py load_audio), so the subprocess gets MediaTools'
    # dependencies-first precedence via PATH — without this, installs whose
    # only ffmpeg is the dependencies/ static build can't transcribe. The
    # resolve call is a preflight: no ffmpeg anywhere raises MediaTools'
    # clear error here instead of a cryptic decode failure inside whisperx.
    MediaTools.ffmpeg
    env = { 'PATH' => [MediaTools::DEPENDENCIES_DIR, ENV.fetch('PATH', '')].join(':') }
    output, status = Open3.capture2e(
      env,
      MediaTools.whisperx, @video_path,
      '--language', @language_code,
      '--model', @whisper_model,
      '--compute_type', 'float32',
      '--device', 'cpu',
      '--output_format', 'json',
      '--output_dir', @output_dir
    )

    if status.success? && File.exist?(transcript_path)
      if empty_transcript?(transcript_path)
        rescue_silent_clip
        return false
      end

      return true
    end

    if output.include?(NO_SPEECH_MARKER)
      rescue_silent_clip
      return false
    end

    raise undecodable_audio_message(output) if output.include?(LOAD_AUDIO_MARKER)
    raise stale_install_message(output, status) if output.include?(PYTHON_TRACEBACK_MARKER)
    raise "whisperx failed for #{clip} (exit #{status.exitstatus})" unless status.success?

    raise no_output_message(output)
  end

  # whisperx 3.8+ answers a silent audio stream with {"segments": []}. Treat
  # that as the rescue case so every silent clip carries the same no-dialogue
  # note, whether or not its file had an audio stream to begin with.
  def empty_transcript?(path)
    Array(JSON.parse(File.read(path))['segments']).empty?
  rescue JSON::ParserError
    false
  end

  # ffprobe saw an audio stream but ffmpeg couldn't decode it (a codec it
  # doesn't handle, a damaged track). That's the footage, not the install, so
  # don't send the user off to reinstall WhisperX.
  def undecodable_audio_message(output)
    tail = output.lines.last(15).join
    <<~MSG
      whisperx couldn't decode the audio in #{clip} — ffmpeg can't read its audio stream. This is the footage, not the WhisperX install.
      Fix: convert the clip with ffmpeg to a supported container and codec, add the converted file to the library, and remove the original entry (see unsupported_media in AGENTS.md for the detect-tell-convert-swap path).
      Last output from ffmpeg:
      #{tail}
    MSG
  end

  # whisperx exited 0 without writing a transcript and without saying it found
  # no speech. This has been reported from the field and not reproduced, so
  # carry whisperx's own output along — it's the only diagnostic a bug report
  # will have.
  def no_output_message(output)
    tail = output.lines.last(15).join
    <<~MSG
      whisperx exited 0 but produced no transcript at #{transcript_path} for #{clip}.
      Last output from whisperx:
      #{tail}
    MSG
  end

  # A Python traceback means whisperx itself crashed rather than choking on the
  # footage. Every known breakage of this kind is a stale venv — packages that
  # drifted from the pinned set (torchaudio 2.9 removed AudioMetaData; torch
  # 2.6 flipped torch.load to weights_only, breaking the VAD checkpoint) — and
  # the fix is the same either way: resync the venv to requirements.txt. This
  # matters most right after an update that changed the pins, since older
  # update flows didn't sync the venv.
  def stale_install_message(output, status)
    tail = output.lines.last(15).join
    # A wrapper script can report 0 for a crash (see MediaTools.whisperx), so
    # only quote the exit status when it says something.
    exit_note = status.success? ? '' : " (exit #{status.exitstatus})"
    <<~MSG
      whisperx crashed with a Python error for #{clip}#{exit_note}. This usually means the WhisperX install is stale or broken, not that the footage is bad.
      Fix: from the ButterCut directory, sync the WhisperX packages to ButterCut's pinned versions:
        ~/.buttercut/venv/bin/pip install --only-binary :all: --no-binary antlr4-python3-runtime,docopt -r requirements.txt
      then retry this clip. If that doesn't fix it, run the setup skill.
      Last output from whisperx:
      #{tail}
    MSG
  end

  def transcript_path
    File.join(@output_dir, "#{File.basename(@video_path, '.*')}.json")
  end

  def rescue_silent_clip
    FileUtils.mkdir_p(@output_dir)
    File.write(transcript_path, JSON.pretty_generate(
      '_note'        => 'no dialogue',
      'segments'     => [],
      'word_segments' => [],
      'video_path'   => @video_path
    ))
  end

  def prepare_transcript
    ok = system('ruby', PREPARE_SCRIPT, transcript_path, @video_path)
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
