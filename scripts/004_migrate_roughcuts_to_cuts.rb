#!/usr/bin/env ruby
# Migration script: Rename the per-library `roughcuts/` directory to `cuts/`.
#
# The `roughcut` skill was renamed to `cut` — it now produces scenes, selects,
# custom tasks, and roughcuts, all into the same output directory. Renaming
# the folder to `cuts/` matches the skill name and the broader set of outputs
# it holds.
#
# Behavior per library:
#   - only `roughcuts/` exists                → rename to `cuts/`
#   - only `cuts/` exists                     → already migrated; skip
#   - neither exists                          → nothing to do; skip
#   - both exist                              → move every file from
#                                               `roughcuts/` into `cuts/`,
#                                               refuse on filename conflict
#                                               (the user must resolve manually
#                                               so nothing gets clobbered), then
#                                               remove the now-empty `roughcuts/`
#
# Usage: ruby scripts/004_migrate_roughcuts_to_cuts.rb [library_name]
#        ruby scripts/004_migrate_roughcuts_to_cuts.rb --all

require 'fileutils'

def migrate_library(library_dir)
  unless File.directory?(library_dir)
    puts "  ✗ Not found: #{library_dir}"
    return false
  end

  old_dir = File.join(library_dir, 'roughcuts')
  new_dir = File.join(library_dir, 'cuts')

  if !File.directory?(old_dir) && File.directory?(new_dir)
    puts '  - Already migrated (cuts/ present, no roughcuts/)'
    return false
  end

  if !File.directory?(old_dir) && !File.directory?(new_dir)
    puts '  - No roughcuts/ or cuts/ directory; nothing to do'
    return false
  end

  if File.directory?(old_dir) && !File.directory?(new_dir)
    File.rename(old_dir, new_dir)
    puts '  ✓ Renamed roughcuts/ → cuts/'
    return true
  end

  # Both exist: merge roughcuts/ into cuts/. Refuse on any name collision so
  # nothing gets overwritten — the user resolves it and re-runs.
  entries = Dir.children(old_dir)
  conflicts = entries.select { |e| File.exist?(File.join(new_dir, e)) }
  unless conflicts.empty?
    puts "  ✗ Cannot merge: #{conflicts.size} filename conflict(s) in cuts/: #{conflicts.join(', ')}"
    puts '    Resolve manually (rename or remove the conflicting file) and re-run.'
    return false
  end

  entries.each { |e| FileUtils.mv(File.join(old_dir, e), File.join(new_dir, e)) }
  Dir.rmdir(old_dir)
  puts "  ✓ Merged #{entries.size} file(s) from roughcuts/ into cuts/ and removed roughcuts/"
  true
end

def find_libraries
  Dir.glob('libraries/*/library.yaml').map { |p| File.dirname(p) }
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts 'Usage: ruby scripts/004_migrate_roughcuts_to_cuts.rb [library_name]'
    puts '       ruby scripts/004_migrate_roughcuts_to_cuts.rb --all'
    exit 1
  end

  if ARGV[0] == '--all'
    libraries = find_libraries
    puts "Migrating #{libraries.length} libraries...\n\n"
    libraries.each do |lib_dir|
      puts "#{File.basename(lib_dir)}:"
      migrate_library(lib_dir)
    end
  else
    library_name = ARGV[0]
    library_dir = "libraries/#{library_name}"
    puts "#{library_name}:"
    migrate_library(library_dir)
  end

  puts "\nMigration complete."
end
