#!/usr/bin/env ruby
# Migration script: Add transcript_refinement to libraries that predate the feature.
#
# Libraries created before the transcript refinement feature existed have no
# `transcript_refinement` key in library.yaml. Their existing transcripts were
# never refined, so we default the key to `false` on migration — we don't want
# the next run to silently opt them in. New libraries still default to `true`
# via the template.
#
# Libraries that already have the key (either `true` or `false`) are left alone.
#
# This migration edits the file textually — it inserts the new line directly
# after the `language:` line without round-tripping through YAML, so quote
# styles and indentation elsewhere in the file are preserved exactly.
#
# Usage: ruby scripts/002_migrate_add_transcript_refinement.rb [library_name]
#        ruby scripts/002_migrate_add_transcript_refinement.rb --all

require 'yaml'

def migrate_library(library_path)
  unless File.exist?(library_path)
    puts "  ✗ Not found: #{library_path}"
    return false
  end

  content = File.read(library_path)

  if content.match?(/^transcript_refinement:/)
    existing = YAML.load(content, permitted_classes: [Date, Time, Symbol])['transcript_refinement']
    puts "  - Already set (#{existing}); no change"
    return false
  end

  lines = content.lines
  language_index = lines.index { |line| line.match?(/^language:/) }

  unless language_index
    puts "  ✗ No top-level `language:` key found; skipping"
    return false
  end

  lines.insert(language_index + 1, "transcript_refinement: false\n")
  new_content = lines.join

  # Sanity check: parse the result to make sure we didn't produce invalid YAML.
  parsed = YAML.load(new_content, permitted_classes: [Date, Time, Symbol])
  unless parsed.is_a?(Hash) && parsed['transcript_refinement'] == false
    puts "  ✗ Insert produced unexpected YAML; refusing to write"
    return false
  end

  File.write(library_path, new_content)
  puts "  ✓ Added transcript_refinement: false"
  true
end

def find_libraries
  Dir.glob("libraries/*/library.yaml")
end

if ARGV.empty?
  puts "Usage: ruby scripts/002_migrate_add_transcript_refinement.rb [library_name]"
  puts "       ruby scripts/002_migrate_add_transcript_refinement.rb --all"
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
