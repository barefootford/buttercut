#!/usr/bin/env ruby
# Migration script: Add media_type to video entries that predate the feature.
#
# Libraries created before audio/image support have no `media_type` key on
# their clip entries. Every such clip is a video file (that was the only kind
# ButterCut handled), so we stamp `media_type: video`. New clips get their kind
# from Library.detect_media_type at add time; the template carries it too.
#
# Clips that already declare `media_type` are left alone.
#
# This migration edits the file textually — it inserts the new line at the top
# of each video list-item (scoped to the `videos:` block) without round-tripping
# through YAML, so quote styles and indentation elsewhere are preserved exactly.
# A parse-and-compare check then confirms nothing but the new media_type changed.
#
# Usage: ruby scripts/005_migrate_add_media_type.rb [library_name]
#        ruby scripts/005_migrate_add_media_type.rb --all

require 'date'
require 'yaml'

def migrate_library(library_path)
  unless File.exist?(library_path)
    puts "  ✗ Not found: #{library_path}"
    return false
  end

  content = File.read(library_path, encoding: 'UTF-8')
  data = YAML.load(content, permitted_classes: [Date, Time, Symbol])
  videos = data.is_a?(Hash) ? data['videos'] : nil

  unless videos.is_a?(Array) && !videos.empty?
    puts '  - No video entries; nothing to migrate'
    return false
  end

  if videos.all? { |v| v.is_a?(Hash) && v.key?('media_type') }
    puts "  - Already set on all #{videos.size} clips; no change"
    return false
  end

  lines = content.lines
  insertions = video_entry_starts(lines).filter_map do |start_idx, key_indent|
    next if entry_has_media_type?(lines, start_idx)

    [start_idx + 1, "#{key_indent}media_type: video\n"]
  end

  if insertions.empty?
    puts '  - No video entries needed the field; no change'
    return false
  end

  # Insert bottom-up so earlier indices stay valid as the array grows.
  insertions.reverse_each { |idx, text| lines.insert(idx, text) }
  new_content = lines.join

  unless safe_insertion?(new_content, data, videos.size)
    puts '  ✗ Insert produced unexpected YAML; refusing to write'
    return false
  end

  File.write(library_path, new_content)
  puts "  ✓ Added media_type: video to #{insertions.size} clip#{'s' unless insertions.size == 1}"
  true
end

# The line index where each video list-item begins, plus the indentation its
# keys sit at. Two precautions keep textual matching honest:
#   1. Only scan inside the top-level `videos:` block, so a list-item bullet
#      that appears inside a multi-line string (e.g. a user_context block
#      scalar containing "- path: ...") is never touched.
#   2. Match the list-item dash marker itself, not specifically `path:`, so an
#      entry whose first key isn't `path` is still recognized.
def video_entry_starts(lines)
  in_videos = false
  lines.each_with_index.filter_map do |line, i|
    if line.match?(/^videos:\s*(\S.*)?$/)
      in_videos = true
      next
    end
    in_videos = false if line.match?(/^\S/) # any other top-level key closes the block
    next unless in_videos
    next unless (match = line.match(/^(\s*)-(\s+)\S/))

    # Keys under a list item align past the "- " marker: dash-line indent plus
    # one column for the dash and the spaces that follow it.
    [i, match[1] + (' ' * (1 + match[2].length))]
  end
end

# True if the entry that begins at `start_idx` already declares media_type —
# on the marker line itself ("- media_type: ...") or any of its key lines.
def entry_has_media_type?(lines, start_idx)
  return true if lines[start_idx].match?(/^\s*-\s+media_type:/)

  ((start_idx + 1)...lines.length).each do |j|
    line = lines[j]
    break if line.match?(/^\s*-\s+\S/) # next list item
    break if line.match?(/^\S/)        # next top-level key
    return true if line.match?(/^\s*media_type:/)
  end
  false
end

# Confirm the only change is that every video now carries a media_type — every
# other top-level field and every other per-clip field is byte-for-byte the same
# as before. Guards against a textual insertion landing anywhere unexpected.
def safe_insertion?(new_content, before, expected_count)
  after = YAML.load(new_content, permitted_classes: [Date, Time, Symbol])
  return false unless after.is_a?(Hash) && after['videos'].is_a?(Array)
  return false unless after['videos'].size == expected_count
  return false unless after.reject { |k, _| k == 'videos' } == before.reject { |k, _| k == 'videos' }

  before['videos'].zip(after['videos']).all? do |was, now|
    now.is_a?(Hash) && now['media_type'] &&
      now.reject { |k, _| k == 'media_type' } == was.reject { |k, _| k == 'media_type' }
  end
end

def find_libraries
  Dir.glob('libraries/*/library.yaml')
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts 'Usage: ruby scripts/005_migrate_add_media_type.rb [library_name]'
    puts '       ruby scripts/005_migrate_add_media_type.rb --all'
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
