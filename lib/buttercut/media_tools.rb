# frozen_string_literal: true

require_relative 'platform'

# Resolves the ffmpeg/ffprobe binaries ButterCut shells out to. Static builds
# may be installed into the gitignored dependencies/ directory at the repo
# root; when a binary is there it wins over PATH, so a ButterCut folder can be
# self-contained with no shell-profile edits for ffmpeg. Machines that rely on
# a suitable ffmpeg on PATH (and have no dependencies/ download) keep using it
# via the bare-name fallback. When a binary is in neither place, resolution
# raises MissingBinary up front — a clear "run the setup skill" instead of a
# cryptic command-not-found buried in subprocess output.
#
# The search order is Platform.find_tool's one ladder, so Windows resolves the
# .exe variants for free.
module MediaTools
  class MissingBinary < StandardError; end

  DEPENDENCIES_DIR = File.expand_path('../../dependencies', __dir__)

  def self.ffmpeg = resolve('ffmpeg')
  def self.ffprobe = resolve('ffprobe')

  def self.resolve(name)
    Platform.find_tool(name, DEPENDENCIES_DIR, :path) ||
      raise(MissingBinary,
            "#{name} not found in ButterCut's dependencies/ directory or on PATH — run the setup skill to install it")
  end
end
