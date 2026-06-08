#!/usr/bin/env ruby
# Migration script: Rename the top-level `videos:` key to `media:`.
#
# Libraries used to hold only video clips, in a `videos:` array. They now hold a
# mixed array of videos and still images, so the key is named `media:`. The array
# contents are unchanged — only the key is renamed. (Image entries are added by
# the normal add-media flow; this migration just brings the key name current.)
#
# Behavior per library:
#   - top-level `videos:` present  → rename to `media:`
#   - already `media:` (no top-level `videos:`) → nothing to do; skip
#
# This migration edits the file textually — it does not round-trip through YAML,
# so quote styles and indentation elsewhere in the file are preserved exactly.
# Only the top-level key (column 0) is touched; nested `transcript:` etc. lines
# are indented and never match.
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

  unless content =~ /^videos:/
    puts "  - No top-level `videos:` key; nothing to do"
    return false
  end

  new_content = content.sub(/^videos:/, 'media:')

  # Sanity check: parse the result and confirm the rename took — valid YAML with a
  # top-level `media:` key and no lingering top-level `videos:`.
  parsed = YAML.load(new_content, permitted_classes: [Date, Time, Symbol])
  unless parsed.is_a?(Hash) && parsed.key?('media') && !parsed.key?('videos')
    puts "  ✗ Rename produced unexpected YAML; refusing to write"
    return false
  end

  File.write(library_path, new_content)
  puts "  ✓ Renamed top-level `videos:` → `media:`"
  true
end

def find_libraries
  Dir.glob("libraries/*/library.yaml")
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts "Usage: ruby scripts/005_migrate_videos_to_media.rb [library_name]"
    puts "       ruby scripts/005_migrate_videos_to_media.rb --all"
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
