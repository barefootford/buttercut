# frozen_string_literal: true

# Resolves the ffmpeg/ffprobe binaries ButterCut shells out to. Static builds
# may be installed into the gitignored dependencies/ directory at the repo
# root; when a binary is there it wins over PATH, so a ButterCut folder can be
# self-contained with no shell-profile edits for ffmpeg. Machines that rely on
# a suitable ffmpeg on PATH (and have no dependencies/ download) keep using it
# via the bare-name fallback.
module MediaTools
  DEPENDENCIES_DIR = File.expand_path('../../dependencies', __dir__)

  def self.ffmpeg = resolve('ffmpeg')
  def self.ffprobe = resolve('ffprobe')

  def self.resolve(name)
    local = File.join(DEPENDENCIES_DIR, name)
    File.executable?(local) ? local : name
  end
end
