#!/usr/bin/env ruby
# frozen_string_literal: true

# Library Backup Utility
# Creates timestamped backups of the entire libraries directory. Uses Apple
# Archive (.aar) when the `aa` CLI is available — hardware-accelerated on
# Apple Silicon, Finder handles double-click extract. Falls back to system
# zip otherwise.

require 'fileutils'
require 'time'

class LibraryBackup
  def initialize(project_root = Dir.pwd)
    @project_root = project_root
    @libraries_dir = File.join(project_root, 'libraries')
    @backups_dir = File.join(project_root, 'backups')
  end

  def backup
    unless Dir.exist?(@libraries_dir)
      puts 'No libraries directory found'
      return nil
    end

    FileUtils.mkdir_p(@backups_dir)
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    aa_available? ? backup_with_apple_archive(timestamp) : backup_with_zip(timestamp)
  end

  private

  def aa_available?
    system('command -v aa > /dev/null 2>&1')
  end

  def backup_with_apple_archive(timestamp)
    backup_path = File.join(@backups_dir, "libraries_#{timestamp}.aar")
    puts "Creating backup: #{backup_path}"
    return nil unless system('aa', 'archive', '-D', @libraries_dir, '-o', backup_path)

    puts 'Backup complete'
    backup_path
  end

  def backup_with_zip(timestamp)
    backup_path = File.join(@backups_dir, "libraries_#{timestamp}.zip")
    puts "Creating backup: #{backup_path}"
    success = Dir.chdir(@project_root) do
      system('zip', '-rq', backup_path, 'libraries')
    end
    return nil unless success

    puts 'Backup complete'
    backup_path
  end
end

if __FILE__ == $PROGRAM_NAME
  LibraryBackup.new.backup
end
