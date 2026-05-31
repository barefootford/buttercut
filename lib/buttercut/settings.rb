#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

# Read-only accessor for libraries/settings.yaml — the user's global ButterCut
# preferences (editor, whisper model, parallelism, …). Centralizes the path so
# callers don't re-parse the file.
#
# settings.yaml is hand-edited and always present once setup has run. Values
# that ship in the template (whisper_model) are read straight from it with no
# code-side default — a blank/missing one is a broken file worth surfacing, not
# something to paper over with a different value than the user configured.
# parallel_jobs is newer and may be absent from an already-created settings.yaml
# (git pull doesn't touch libraries/), so it alone carries a fallback default.
class Settings
  PATH = File.expand_path('../../libraries/settings.yaml', __dir__)

  DEFAULT_PARALLEL_JOBS = 2 # WhisperX is RAM-hungry; 2 is the safe default.

  def self.load(path: PATH) = new(path: path)

  def initialize(path: PATH)
    @data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
  end

  # How many mechanical jobs (transcription, contact sheets) to run in parallel.
  # Blank / missing / non-positive / non-numeric → DEFAULT_PARALLEL_JOBS.
  def parallel_jobs
    n = Integer(@data['parallel_jobs'], exception: false)
    n && n >= 1 ? n : DEFAULT_PARALLEL_JOBS
  end

  # WhisperX model size, straight from settings.yaml — no code default. The
  # template ships `whisper_model` and setup writes it, so a blank/missing value
  # means a broken settings.yaml.
  def whisper_model
    value = @data['whisper_model'].to_s.strip
    raise 'whisper_model is not set in libraries/settings.yaml (expected tiny/base/small/medium/turbo)' if value.empty?

    value
  end
end
