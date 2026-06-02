require 'spec_helper'
require_relative '../../lib/buttercut/job'
require_relative '../../lib/buttercut/job_runner'

# In-memory stand-in for Library: records completions thread-safely so we can
# assert what the runner wrote without touching disk or library.yaml.
class RunnerFakeLibrary
  attr_reader :completed

  def initialize
    @completed = []
    @mutex = Mutex.new
  end

  def name = 'fake-lib'

  def complete!(field, clips, announce: true)
    @mutex.synchronize { Array(clips).each { |c| @completed << [field, c] } }
    self
  end
end

# Tracks how many jobs are running at once, so a cap can be asserted.
class RunnerConcurrencyTracker
  attr_reader :max

  def initialize
    @current = 0
    @max = 0
    @mutex = Mutex.new
  end

  def enter = @mutex.synchronize { @current += 1; @max = [@max, @current].max }
  def leave = @mutex.synchronize { @current -= 1 }
end

# Test job: no shelling out. Optionally sleeps (to force overlap) and/or fails.
class RunnerFakeJob < Job
  def self.field = 'transcript'

  def initialize(clip:, field: 'transcript', tracker: nil, fail: false, sleep_for: 0.0)
    super(library_name: 'fake-lib', clip: clip)
    @field = field
    @tracker = tracker
    @fail = fail
    @sleep_for = sleep_for
  end

  def field = @field

  def perform
    @tracker&.enter
    sleep(@sleep_for) if @sleep_for.positive?
    raise "boom #{clip}" if @fail

    self
  ensure
    @tracker&.leave
  end
end

RSpec.describe JobRunner do
  let(:library) { RunnerFakeLibrary.new }
  let(:devnull) { File.open(File::NULL, 'w') }
  subject(:runner) { described_class.new(library, io: devnull) }

  after { devnull.close }

  def jobs(*clips, **opts)
    clips.map { |c| RunnerFakeJob.new(clip: c, **opts) }
  end

  it 'records every successful job to the library exactly once' do
    results = runner.run(jobs('a.mov', 'b.mov', 'c.mov'), concurrency: 2)

    expect(results.map(&:ok)).to all(be(true))
    expect(library.completed).to contain_exactly(
      %w[transcript a.mov], %w[transcript b.mov], %w[transcript c.mov]
    )
  end

  it 'never exceeds the concurrency cap' do
    tracker = RunnerConcurrencyTracker.new
    clips = Array.new(12) { |i| "clip#{i}.mov" }
    runner.run(jobs(*clips, tracker: tracker, sleep_for: 0.03), concurrency: 3)

    expect(tracker.max).to be <= 3
    expect(tracker.max).to be > 1 # proves it actually ran in parallel
  end

  it 'isolates failures: other jobs still run, failed ones are not recorded' do
    batch = [
      RunnerFakeJob.new(clip: 'ok1.mov'),
      RunnerFakeJob.new(clip: 'bad.mov', fail: true),
      RunnerFakeJob.new(clip: 'ok2.mov')
    ]
    results = runner.run(batch, concurrency: 3)

    expect(results.size).to eq(3)
    failed = results.reject(&:ok)
    expect(failed.map(&:clip)).to eq(['bad.mov'])
    expect(failed.first.error.message).to eq('boom bad.mov')
    expect(library.completed).to contain_exactly(%w[transcript ok1.mov], %w[transcript ok2.mov])
  end

  it 'accumulates across successive run() calls (transcripts, then sheets)' do
    # Mirrors process_footage.rb: one step finishes before the next starts.
    transcripts = runner.run(jobs('a.mov', 'b.mov', field: 'transcript'), concurrency: 2)
    sheets = runner.run(jobs('a.mov', 'b.mov', field: 'contact_sheet'), concurrency: 2)

    expect(transcripts.map(&:field)).to all(eq('transcript'))
    expect(sheets.map(&:field)).to all(eq('contact_sheet'))
    expect(library.completed).to contain_exactly(
      %w[transcript a.mov], %w[transcript b.mov],
      %w[contact_sheet a.mov], %w[contact_sheet b.mov]
    )
  end

  it 'treats a recording failure as a job failure' do
    allow(library).to receive(:complete!).and_raise(ArgumentError, 'transcript file does not exist')
    results = runner.run(jobs('a.mov'), concurrency: 1)

    expect(results.first.ok).to be(false)
    expect(results.first.error.message).to eq('transcript file does not exist')
  end

  it 'is a no-op when there are no jobs to run' do
    expect(runner.run([])).to eq([])
    expect(library.completed).to be_empty
  end

  describe 'concurrency from settings.yaml' do
    it 'falls back to Settings#parallel_jobs when run omits a cap' do
      allow(Settings).to receive(:load).and_return(instance_double(Settings, parallel_jobs: 1))
      tracker = RunnerConcurrencyTracker.new
      clips = Array.new(5) { |i| "clip#{i}.mov" }

      # No concurrency passed anywhere → runner reads settings (1) → fully serial.
      runner.run(jobs(*clips, tracker: tracker, sleep_for: 0.02))

      expect(tracker.max).to eq(1)
    end

    it 'prefers an explicit constructor concurrency over settings' do
      allow(Settings).to receive(:load).and_return(instance_double(Settings, parallel_jobs: 1))
      pinned = described_class.new(library, concurrency: 3, io: devnull)
      tracker = RunnerConcurrencyTracker.new
      clips = Array.new(9) { |i| "clip#{i}.mov" }

      pinned.run(jobs(*clips, tracker: tracker, sleep_for: 0.03))

      expect(tracker.max).to be > 1
      expect(tracker.max).to be <= 3
    end
  end
end
