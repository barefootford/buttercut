#!/usr/bin/env ruby
# Migration script: Add `summary` field to video entries that predate the
# summarize-video skill.
#
# The summarize-video skill produces a short markdown summary of each video
# from its visual transcript. Libraries created before that skill existed have
# no `summary:` key in their video entries. Missing means "todo" — the same
# convention as `transcript:` and `visual_transcript:`. The migration inserts
# an empty `summary:` line directly after each `visual_transcript:` line.
#
# Video entries that already have `summary:` are left alone. Video entries
# without `visual_transcript:` (mid-pipeline videos) are skipped — they'll get
# a `summary:` field added by the parent agent when their visual transcript is
# produced.
#
# This migration edits the file textually — it does not round-trip through
# YAML, so quote styles and indentation elsewhere in the file are preserved
# exactly.
#
# Usage: ruby scripts/003_migrate_add_summary.rb [library_name]
#        ruby scripts/003_migrate_add_summary.rb --all

require 'yaml'

def migrate_library(library_path)
  unless File.exist?(library_path)
    puts "  ✗ Not found: #{library_path}"
    return false
  end

  content = File.read(library_path)
  lines = content.lines

  inserts = []
  lines.each_with_index do |line, i|
    next unless line =~ /^(\s+)visual_transcript:/
    indent = $1
    next_line = lines[i + 1]
    next if next_line && next_line.match?(/^#{Regexp.escape(indent)}summary:/)
    inserts << [i + 1, "#{indent}summary:\n"]
  end

  if inserts.empty?
    puts "  - All applicable video entries already have `summary:`; no change"
    return false
  end

  inserts.reverse_each { |idx, text| lines.insert(idx, text) }
  new_content = lines.join

  # Sanity check: parse the result to make sure we didn't produce invalid YAML.
  parsed = YAML.load(new_content, permitted_classes: [Date, Time, Symbol])
  unless parsed.is_a?(Hash) && parsed['videos'].is_a?(Array)
    puts "  ✗ Insert produced unexpected YAML; refusing to write"
    return false
  end

  File.write(library_path, new_content)
  noun = inserts.length == 1 ? "entry" : "entries"
  puts "  ✓ Added `summary:` to #{inserts.length} video #{noun}"
  true
end

def find_libraries
  Dir.glob("libraries/*/library.yaml")
end

if ARGV.empty?
  puts "Usage: ruby scripts/003_migrate_add_summary.rb [library_name]"
  puts "       ruby scripts/003_migrate_add_summary.rb --all"
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
