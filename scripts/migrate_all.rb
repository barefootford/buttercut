#!/usr/bin/env ruby
# frozen_string_literal: true

# Run every migration script against every library in one pass.
#
# Each individual script is idempotent — it skips libraries that are already
# current — so this is safe to re-run at any time.
#
# Usage: ruby scripts/migrate_all.rb

SCRIPTS_DIR = File.expand_path(__dir__)
REPO_ROOT = File.expand_path('..', SCRIPTS_DIR)
Dir.chdir(REPO_ROOT)

MIGRATIONS = Dir.glob(File.join(SCRIPTS_DIR, '[0-9]*_migrate_*.rb')).sort

if MIGRATIONS.empty?
  puts 'No migration scripts found.'
  exit 0
end

puts "Running #{MIGRATIONS.size} migration(s) across all libraries...\n\n"

failed = []
MIGRATIONS.each do |script|
  name = File.basename(script)
  puts "=== #{name} ==="
  system('ruby', script, '--all')
  failed << name unless $?.success?
  puts
end

if failed.empty?
  puts 'All migrations complete.'
else
  warn "#{failed.size} migration(s) failed: #{failed.join(', ')}"
  exit 1
end
