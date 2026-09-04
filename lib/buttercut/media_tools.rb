# frozen_string_literal: true

require %q(open3)

# Resolves the ffmpeg/ffprobe binaries ButterCut shells out to. Static builds
# may be installed into the gitignored dependencies/ directory at the repo
# root; when a binary is there it wins over PATH, so a ButterCut folder can be
# self-contained with no shell-profile edits for ffmpeg. Machines that rely on
# a suitable ffmpeg on PATH (and have no dependencies/ download) keep using it
# via the bare-name fallback. When a binary is in neither place, resolution
# raises MissingBinary up front — a clear "run the setup skill" instead of a
# cryptic command-not-found buried in subprocess output.
module MediaTools
  class MissingBinary < StandardError; end

  DEPENDENCIES_DIR = File.expand_path('../../dependencies', __dir__)

  def self.ffmpeg = resolve('ffmpeg')
  def self.ffprobe = resolve('ffprobe')

  # The setup skill installs WhisperX into this venv and puts a wrapper script
  # on PATH. Wrappers written before 2026-09 ended with `deactivate`, so the
  # shell reported *its* exit status — 0 — no matter how whisperx died, and a
  # crash looked like a clean run that wrote no transcript. Calling the venv
  # binary directly sidesteps every wrapper ever installed; the bare name is
  # the fallback for installs that keep whisperx somewhere else.
  WHISPERX_VENV_BIN = File.expand_path('~/.buttercut/venv/bin/whisperx')

  def self.whisperx
    return WHISPERX_VENV_BIN if File.executable?(WHISPERX_VENV_BIN)

    'whisperx'
  end

  def self.resolve(name)
    local = File.join(DEPENDENCIES_DIR, name)
    return local if File.executable?(local)
    return name if on_path?(name)

    raise MissingBinary,
          "#{name} not found in ButterCut's dependencies/ directory or on PATH — run the setup skill to install it"
  end

  def self.on_path?(name)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
      !dir.empty? && File.executable?(File.join(dir, name))
    end
  end

  # True when ffprobe finds at least one audio stream in the file. Picture-only
  # recordings — many drone bodies, some action cams, screen captures — have
  # none, and handing one to WhisperX only makes the ffmpeg decode inside it
  # fail. If ffprobe itself can't read the file, answer true: the transcription
  # step will then hit the real problem against the real tool and report that.
  def self.audio_stream?(path)
    output, status = Open3.capture2e(
      ffprobe, '-v', 'error', '-select_streams', 'a',
      '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', path
    )
    return true unless status.success?

    output.lines.any? { |line| line.strip == 'audio' }
  end
end
