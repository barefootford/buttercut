#!/usr/bin/env ruby
require 'json'
require 'fileutils'

# Usage: combine_to_timeline.rb [library_name] [timeline_name]
library_name = ARGV[0]
timeline_name = ARGV[1]

if library_name.nil? || timeline_name.nil?
  puts "Usage: combine_to_timeline.rb [library_name] [timeline_name]"
  exit 1
end

# Find all audio transcript files (exclude visual_* files)
transcripts_dir = "libraries/#{library_name}/transcripts"
audio_files = Dir.glob("#{transcripts_dir}/*.json")
  .reject { |f| File.basename(f).start_with?('visual_') }
  .sort

if audio_files.empty?
  puts "No audio transcripts found in #{transcripts_dir}"
  exit 1
end

# Create output directory
output_dir = "tmp/#{library_name}"
FileUtils.mkdir_p(output_dir)
output_file = "#{output_dir}/#{timeline_name}_timeline.txt"

files_included = 0

File.open(output_file, 'w') do |out|
  audio_files.each do |file|
    data = JSON.parse(File.read(file))

    # Derive video filename from transcript filename
    # e.g., "DJI_20250423171212_0210_D.json" -> "DJI_20250423171212_0210_D"
    filename = File.basename(file, '.json')

    # Collect non-empty segments
    segments = data['segments'] || []
    dialogue_segments = segments.select { |s| s['text'].to_s.strip != '' }

    # Skip files with no dialogue (B-roll only)
    next if dialogue_segments.empty?

    # Add newline between files (except before first)
    out.puts if files_included > 0

    # Write file header
    out.puts "=== #{filename} ==="
    out.puts

    # Write each segment
    dialogue_segments.each do |segment|
      start_time = segment['start']
      end_time = segment['end']
      text = segment['text'].to_s.strip

      out.puts "[#{start_time}-#{end_time}] #{text}"
      out.puts
    end

    files_included += 1
  end
end

puts "Combined #{files_included} of #{audio_files.length} audio transcripts (#{audio_files.length - files_included} B-roll skipped) -> #{output_file}"
