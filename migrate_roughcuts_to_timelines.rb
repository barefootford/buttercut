#!/usr/bin/env ruby
# Migration script: Rename roughcuts/ directories to timelines/
# Run from buttercut root: ruby migrate_roughcuts_to_timelines.rb

require 'fileutils'

LIBRARIES_DIR = File.join(__dir__, 'libraries')

unless Dir.exist?(LIBRARIES_DIR)
  puts "No libraries directory found at #{LIBRARIES_DIR}"
  exit 0
end

libraries = Dir.glob(File.join(LIBRARIES_DIR, '*')).select { |f| File.directory?(f) }

if libraries.empty?
  puts "No libraries found to migrate."
  exit 0
end

migrated = 0
skipped = 0

libraries.each do |lib_path|
  lib_name = File.basename(lib_path)
  roughcuts_dir = File.join(lib_path, 'roughcuts')
  timelines_dir = File.join(lib_path, 'timelines')

  if Dir.exist?(timelines_dir)
    puts "  [skip] #{lib_name}: timelines/ already exists"
    skipped += 1
  elsif Dir.exist?(roughcuts_dir)
    FileUtils.mv(roughcuts_dir, timelines_dir)
    puts "  [migrated] #{lib_name}: roughcuts/ -> timelines/"
    migrated += 1
  else
    puts "  [skip] #{lib_name}: no roughcuts/ directory"
    skipped += 1
  end
end

puts
puts "Migration complete: #{migrated} migrated, #{skipped} skipped"
