#!/usr/bin/env ruby
# Prepares visual-transcript-ready JSONs for many clips at once.
# For each pair, copies the audio transcript to the visual transcript path,
# strips word-level timing, and prettifies the JSON.
#
# Reads tab-separated lines from a manifest file:
#   <audio_transcript_path>\t<visual_transcript_path>
#
# Writes one line per pair to stdout:
#   ✓ <visual_transcript_path>
#   ✗ <visual_transcript_path> → ERROR: <message>

require 'fileutils'
require 'json'

class BatchPrepareVisualScripts
  def self.perform(manifest_path:)
    new(manifest_path: manifest_path).perform
  end

  def initialize(manifest_path:)
    raise ArgumentError, "manifest_path required" if manifest_path.nil? || manifest_path.empty?
    raise ArgumentError, "manifest file not found: #{manifest_path}" unless File.exist?(manifest_path)
    @manifest_path = manifest_path
  end

  def perform
    jobs = read_manifest
    jobs.each { |audio, visual| prepare(audio, visual) }
  end

  private

  def read_manifest
    File.readlines(@manifest_path, chomp: true).reject(&:empty?).map do |line|
      audio, visual = line.split("\t", 2)
      raise "bad manifest line: #{line.inspect}" if audio.nil? || visual.nil?
      [audio, visual]
    end
  end

  def prepare(audio, visual)
    FileUtils.cp(audio, visual)
    data = JSON.parse(File.read(visual))
    data['segments']&.each { |s| s.delete('words') }
    data.delete('word_segments')

    reordered = {}
    reordered['language'] = data['language'] if data['language']
    reordered['video_path'] = data['video_path'] if data['video_path']
    reordered['segments'] = data['segments'] if data['segments']
    data.each { |k, v| reordered[k] = v unless reordered.key?(k) }

    File.write(visual, JSON.pretty_generate(reordered))
    puts "✓ #{visual}"
  rescue => e
    puts "✗ #{visual} → ERROR: #{e.message}"
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    warn "usage: batch_prepare_visual_scripts.rb <manifest_file>"
    exit 1
  end
  BatchPrepareVisualScripts.perform(manifest_path: ARGV[0])
end
