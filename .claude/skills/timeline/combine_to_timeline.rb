#!/usr/bin/env ruby
require 'json'
require 'fileutils'

# Usage: combine_to_timeline.rb [library_name]
library_name = ARGV[0]

if library_name.nil?
  puts "Usage: combine_to_timeline.rb [library_name]"
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
output_file = "#{output_dir}/timeline.txt"

# Extract visual summary from visual transcript
def extract_visual_summary(transcripts_dir, filename)
  visual_file = "#{transcripts_dir}/visual_#{filename}.json"
  return nil unless File.exist?(visual_file)

  visual_data = JSON.parse(File.read(visual_file))
  segments = visual_data['segments'] || []

  # Get first visual description (usually the most detailed)
  first_visual = segments.find { |s| s['visual'] }&.dig('visual')
  return nil unless first_visual

  # Count B-roll segments
  b_roll_count = segments.count { |s| s['b_roll'] }

  # Build summary
  summary = first_visual.split('.').first(2).join('.') + '.'
  summary += " Includes #{b_roll_count} B-roll segments." if b_roll_count > 0
  summary
end

files_included = 0
b_roll_included = 0

File.open(output_file, 'w') do |out|
  audio_files.each do |file|
    data = JSON.parse(File.read(file))
    filename = File.basename(file, '.json')
    segments = data['segments'] || []

    # Separate dialogue and B-roll segments
    dialogue_segments = segments.select { |s| s['text'].to_s.strip != '' }
    is_b_roll_only = dialogue_segments.empty?

    # Get visual summary
    visual_summary = extract_visual_summary(transcripts_dir, filename)

    # Skip B-roll files that have no visual description
    next if is_b_roll_only && visual_summary.nil?

    # Add newline between files (except before first)
    out.puts if files_included > 0

    # Write file header
    out.puts "=== #{filename} ==="

    # Write visual summary if available
    if visual_summary
      out.puts "VISUAL: #{visual_summary}"
    end
    out.puts

    if is_b_roll_only
      # For B-roll only files, note it explicitly
      out.puts "[B-ROLL] No dialogue"
      out.puts
      b_roll_included += 1
    else
      # Write each dialogue segment
      dialogue_segments.each do |segment|
        start_time = segment['start']
        end_time = segment['end']
        text = segment['text'].to_s.strip
        out.puts "[#{start_time}-#{end_time}] #{text}"
        out.puts
      end
    end

    files_included += 1
  end
end

puts "Combined #{files_included} files (#{b_roll_included} B-roll only) -> #{output_file}"
