#!/usr/bin/env ruby
# frozen_string_literal: true

# Migration script: rename the top-level `videos:` key to `media:`.
#
# Libraries now hold mixed media (videos + images), so the array is called
# `media`. That key rename is the whole migration — no per-entry changes,
# because the media type is inferred from each entry's file extension, and
# every pre-migration entry is a video by definition.
#
# This migration edits the file textually — it does not round-trip through
# YAML, so quote styles and indentation elsewhere in the file are preserved
# exactly.
#
# Usage: ruby scripts/005_migrate_videos_to_media.rb [library_name]
#        ruby scripts/005_migrate_videos_to_media.rb --all

require 'date'
require 'yaml'

def migrate_library(library_path)
  unless File.exist?(library_path)
    puts "  ✗ Not found: #{library_path}"
    return false
  end

  content = File.read(library_path, encoding: 'UTF-8')

  if content.match?(/^media:/)
    puts '  - Already uses `media:`; no change'
    return false
  end

  unless content.match?(/^videos:/)
    puts '  - No top-level `videos:` key found; no change'
    return false
  end

  new_content = content.sub(/^videos:/, 'media:')

  # Sanity check: parse the result to make sure we didn't produce invalid YAML.
  parsed = YAML.load(new_content, permitted_classes: [Date, Time, Symbol])
  unless parsed.is_a?(Hash) && parsed['media'].is_a?(Array)
    puts '  ✗ Rename produced unexpected YAML; refusing to write'
    return false
  end

  File.write(library_path, new_content)
  puts '  ✓ Renamed `videos:` to `media:`'
  true
end

def find_libraries
  Dir.glob('libraries/*/library.yaml')
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts 'Usage: ruby scripts/005_migrate_videos_to_media.rb [library_name]'
    puts '       ruby scripts/005_migrate_videos_to_media.rb --all'
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
end
