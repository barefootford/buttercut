#!/usr/bin/env ruby
# Migration script: Convert full transcript paths to filenames in library.yaml
#
# Before:
#   transcript_path: "/Users/.../transcripts/video.json"
#   visual_transcript_path: "/Users/.../transcripts/visual_video.json"
#
# After:
#   transcript: "video.json"
#   visual_transcript: "visual_video.json"
#
# Usage: ruby scripts/migrate_library_yaml.rb [library_name]
#        ruby scripts/migrate_library_yaml.rb --all

require 'yaml'
require 'fileutils'

def migrate_library(library_path)
  unless File.exist?(library_path)
    puts "  ✗ Not found: #{library_path}"
    return false
  end

  content = File.read(library_path)
  data = YAML.load(content, permitted_classes: [Date, Time, Symbol])

  return false unless data['videos']

  changes = 0
  data['videos'].each do |video|
    # Migrate transcript_path -> transcript
    if video['transcript_path']
      video['transcript'] = File.basename(video['transcript_path'])
      video.delete('transcript_path')
      changes += 1
    end

    # Migrate visual_transcript_path -> visual_transcript
    if video['visual_transcript_path']
      video['visual_transcript'] = File.basename(video['visual_transcript_path'])
      video.delete('visual_transcript_path')
      changes += 1
    end

    # Remove file_size_mb (no longer needed)
    if video['file_size_mb']
      video.delete('file_size_mb')
      changes += 1
    end
  end

  if changes > 0
    # Write migrated file
    File.write(library_path, data.to_yaml)
    puts "  ✓ Migrated #{changes} fields"
    true
  else
    puts "  - No changes needed"
    false
  end
end

def find_libraries
  Dir.glob("libraries/*/library.yaml")
end

# Main
if ARGV.empty?
  puts "Usage: ruby scripts/migrate_library_yaml.rb [library_name]"
  puts "       ruby scripts/migrate_library_yaml.rb --all"
  exit 1
end

if ARGV[0] == '--all'
  libraries = find_libraries
  puts "Migrating #{libraries.length} libraries...\n\n"

  libraries.each do |lib_path|
    lib_name = lib_path.split('/')[1]
    puts "#{lib_name}:"
    migrate_library(lib_path)
  end
else
  library_name = ARGV[0]
  library_path = "libraries/#{library_name}/library.yaml"
  puts "#{library_name}:"
  migrate_library(library_path)
end

puts "\nMigration complete."
