#!/usr/bin/env ruby
# frozen_string_literal: true

# Base class for ButterCut's mechanical processing jobs.
#
# These are the deterministic, shell-out steps of footage analysis — running
# WhisperX, building contact sheets with ffmpeg — that used to be orchestrated
# from a skill prompt, and so came out differently depending on which model read
# the prompt (different ordering, parallelism, batching). Moving them into Jobs
# makes the work identical on every run, whichever agent kicks it off.
#
# Modeled on Active Job / Sidekiq so the shape is familiar to people and agents:
#
#   * one job == one unit of work (one clip), done in #perform
#   * idempotent: safe to run again; re-running only rebuilds its own artifact
#   * never touches library.yaml — JobRunner owns concurrency and every write
#
# A job is a pure function of the inputs handed to its constructor. It does NOT
# read library.yaml or settings.yaml; the runner resolves those once up front
# and passes concrete values in. That keeps jobs trivial to test and removes any
# reader/writer race against the runner's library.yaml writes.
#
# Subclass contract:
#   .field   — the library.yaml field a successful run completes ('transcript')
#   #perform — do the work for one clip; return self; raise on failure
class Job
  # The library.yaml field a successful run marks complete. Subclasses override.
  def self.field = raise(NotImplementedError, "#{self} must define .field")

  # Sidekiq-style synchronous entry point: Job.perform_now(**kwargs).
  def self.perform_now(...) = new(...).perform

  attr_reader :library_name, :clip

  def initialize(library_name:, clip:)
    raise ArgumentError, 'library_name is required' if library_name.to_s.strip.empty?
    raise ArgumentError, 'clip is required' if clip.to_s.strip.empty?

    @library_name = library_name
    @clip = clip
  end

  def field = self.class.field

  # Do the work for one clip. Must be idempotent. Return self; raise on failure.
  def perform = raise(NotImplementedError, "#{self.class} must implement #perform")

  # Label used in the runner's progress output.
  def to_s = "#{self.class.name}(#{clip})"
end
