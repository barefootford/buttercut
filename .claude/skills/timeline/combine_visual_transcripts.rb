#!/usr/bin/env ruby
require 'fileutils'

# Usage: combine_visual_transcripts.rb [library_name] [roughcut_name]
library_name = ARGV[0]
roughcut_name = ARGV[1]

if library_name.nil? || roughcut_name.nil?
  puts "Usage: combine_visual_transcripts.rb [library_name] [roughcut_name]"
  exit 1
end

# Find all visual transcript files
transcripts_dir = "libraries/#{library_name}/transcripts"
visual_files = Dir.glob("#{transcripts_dir}/visual_*.json").sort

if visual_files.empty?
  puts "No visual transcripts found in #{transcripts_dir}"
  exit 1
end

# Concatenate all visual transcripts with newlines
output_dir = "tmp/#{library_name}"
FileUtils.mkdir_p(output_dir)
output_file = "#{output_dir}/#{roughcut_name}_combined_visual_transcript.json"

File.open(output_file, 'w') do |out|
  visual_files.each_with_index do |file, index|
    out.write(File.read(file))
    out.write("\n") unless index == visual_files.length - 1
  end
end

puts "Combined #{visual_files.length} visual transcripts -> #{output_file}"
