#!/usr/bin/env ruby
# Builds grid montages for multiple clips in parallel.
#
# Reads tab-separated lines from a manifest file: <video_path>\t<output_path>
# Runs N clips concurrently (default 8). Each clip still extracts its adaptive
# tile set sequentially via grid_montage.rb's existing pipeline; concurrency
# happens across clips. Peak RSS ≈ ~600MB per concurrent clip.
#
# Writes one line per clip to stdout: <video_path>\t<grid_path>[,grid_path...]
# or <video_path>\tERROR: <message> on failure.

require_relative 'grid_montage'

class BatchGridMontage
  DEFAULT_CONCURRENCY = 8

  def self.perform(manifest_path:, concurrency: DEFAULT_CONCURRENCY)
    new(manifest_path: manifest_path, concurrency: concurrency).perform
  end

  def initialize(manifest_path:, concurrency:)
    raise ArgumentError, "manifest_path required" if manifest_path.nil? || manifest_path.empty?
    raise ArgumentError, "manifest file not found: #{manifest_path}" unless File.exist?(manifest_path)
    @manifest_path = manifest_path
    @concurrency = concurrency
  end

  def perform
    jobs = read_manifest
    results = run_in_parallel(jobs)
    print_results(jobs, results)
  end

  private

  def read_manifest
    File.readlines(@manifest_path, chomp: true).reject(&:empty?).map do |line|
      video_path, output_path = line.split("\t", 2)
      raise "bad manifest line: #{line.inspect}" if video_path.nil? || output_path.nil?
      [video_path, output_path]
    end
  end

  def run_in_parallel(jobs)
    queue = Queue.new
    jobs.each { |job| queue << job }
    results = {}
    mutex = Mutex.new
    threads = @concurrency.times.map do
      Thread.new do
        loop do
          video_path, output_path = begin
            queue.pop(true)
          rescue ThreadError
            break
          end
          begin
            grid_paths = GridMontage.build(video_path: video_path, output_path: output_path)
            mutex.synchronize { results[video_path] = grid_paths }
          rescue => e
            mutex.synchronize { results[video_path] = "ERROR: #{e.message}" }
          end
        end
      end
    end
    threads.each(&:join)
    results
  end

  def print_results(jobs, results)
    jobs.each do |video_path, _|
      value = results[video_path]
      if value.is_a?(Array)
        puts "#{video_path}\t#{value.join(',')}"
      else
        puts "#{video_path}\t#{value}"
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    warn "usage: batch_grid_montage.rb <manifest_file> [concurrency]"
    exit 1
  end
  BatchGridMontage.perform(
    manifest_path: ARGV[0],
    concurrency: (ARGV[1] || BatchGridMontage::DEFAULT_CONCURRENCY).to_i,
  )
end
