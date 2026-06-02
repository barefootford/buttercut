#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs a list of Jobs over a small thread pool and records each success to
# library.yaml.
#
# This is ButterCut's in-process stand-in for a Sidekiq worker pool. It owns the
# two things a Job must never touch: concurrency and library.yaml. Jobs are pure
# (see job.rb). The runner records each success through `Library#complete!`,
# whose flock-guarded transaction serializes writes across both these worker
# threads and any other process (e.g. the agent updating footage_summary while
# this run records transcripts) — so the runner needs no write mutex of its own.
#
# Why threads, not processes: the real work is in subprocesses (whisperx,
# ffmpeg), so Ruby releases the GIL while they run — a thread pool gets full
# parallelism with none of the fork/IPC overhead.
#
# Scope is deliberately small: one `run(jobs)` call drains one flat list of
# same-kind jobs, a couple at a time. The runner knows nothing about ordering —
# that's the caller's job. process_footage.rb runs the transcripts step to
# completion, then the contact-sheets step, as two separate `run` calls, so the
# slow step (whisperx) never overlaps the fast one and total concurrency stays
# at the cap, not double it.
#
# Backend seam: today the "queue" is an in-memory array drained by threads. The
# shape is deliberately Sidekiq-ish so a future Solid Queue / Sidekiq adapter
# (e.g. ButterCut Pro's background service) could slot in behind it without
# changing callers. library.yaml stays the one ledger of done/not-done.
#
# Concurrency comes from one knob: settings.yaml's `parallel_jobs` (default 2).
# A caller can override per-run via `run(jobs, concurrency:)`, or pin a default
# via `JobRunner.new(library, concurrency:)`.
require 'fileutils'
require_relative 'settings'

class JobRunner
  ACTIVE_ROOT = File.expand_path('../../tmp/active', __dir__)
  Result = Struct.new(:job, :ok, :error, keyword_init: true) do
    def field = job.field
    def clip = job.clip
  end

  def initialize(library, concurrency: nil, io: $stdout)
    @library = library
    @explicit_concurrency = concurrency
    @io = io
    @io_mutex = Mutex.new
  end

  # Run every job through a pool of at most `concurrency` workers — falling back
  # to the runner's configured cap, then settings.yaml's `parallel_jobs`
  # (default 2). Returns a flat array of Results in completion order. Never
  # raises for a failed job — failures come back as Results with ok: false so
  # the caller can summarize and set an exit code.
  def run(jobs, concurrency: nil)
    jobs = Array(jobs)
    return [] if jobs.empty?

    cap = concurrency || @explicit_concurrency || settings_concurrency
    raise ArgumentError, 'concurrency must be >= 1' if cap < 1

    queue = Thread::Queue.new
    jobs.each { |job| queue << job }
    sink = Thread::Queue.new # thread-safe, so workers append without a mutex

    workers = Array.new([cap, jobs.size].min) do
      Thread.new do
        while (job = next_job(queue))
          log('start', job)
          result = run_one(job)
          sink << result
          result.ok ? log('done', job) : log('error', job, result.error.message)
        end
      end
    end
    workers.each(&:join)
    clear_active
    drain(sink)
  end

  private

  def settings_concurrency = @settings_concurrency ||= Settings.load.parallel_jobs

  def next_job(queue)
    queue.pop(true)
  rescue ThreadError # queue empty, non-blocking pop
    nil
  end

  # Empty a queue into an array. Called after every worker has joined, so there
  # are no concurrent pushes to race with.
  def drain(queue)
    results = []
    results << queue.pop until queue.empty?
    results
  end

  # Perform the job, then — on success — record it to library.yaml. The write is
  # serialized by Library's flock transaction and counts as part of the job: if
  # recording fails, the job fails.
  def run_one(job)
    mark_active(job)
    job.perform
    @library.complete!(job.field, [job.clip], announce: false)
    Result.new(job: job, ok: true)
  rescue StandardError => e
    Result.new(job: job, ok: false, error: e)
  ensure
    unmark_active(job)
  end

  def active_path(job)
    File.join(ACTIVE_ROOT, @library.name, job.field, job.clip)
  end

  def mark_active(job)
    path = active_path(job)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.touch(path)
  end

  def unmark_active(job)
    path = active_path(job)
    File.delete(path) if File.exist?(path)
  end

  def clear_active
    dir = File.join(ACTIVE_ROOT, @library.name)
    FileUtils.rm_rf(dir) if Dir.exist?(dir)
  end

  # One line per job event — start, done, or error — naming the job by its own
  # class and clip (both intrinsic to the job). The runner still tracks no batch
  # totals and carries none of the orchestrator's step framing.
  def log(event, job, detail = nil)
    line = "#{job.class.name}  #{event.ljust(5)}  #{job.clip}"
    line = "#{line} — #{detail}" if detail
    @io_mutex.synchronize { @io.puts line }
  end
end
