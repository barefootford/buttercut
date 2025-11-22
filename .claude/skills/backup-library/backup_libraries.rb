#!/usr/bin/env ruby
# frozen_string_literal: true

# Library Backup Utility
# Creates compressed ZIP backups of the entire libraries directory

require 'fileutils'
require 'time'
require 'zip'

class LibraryBackup
  def initialize(project_root = Dir.pwd)
    @libraries_dir = File.join(project_root, 'libraries')
    @backups_dir = File.join(project_root, 'backups')
  end

  def backup
    unless Dir.exist?(@libraries_dir)
      puts "❌ No libraries directory found"
      return nil
    end

    FileUtils.mkdir_p(@backups_dir)

    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_path = File.join(@backups_dir, "libraries_#{timestamp}.zip")

    puts "📦 Creating backup: #{backup_path}"

    files = Dir.glob(File.join(@libraries_dir, '**', '*')).select { |f| File.file?(f) }

    Zip::File.open(backup_path, Zip::File::CREATE) do |zipfile|
      files.each do |file|
        zipfile.add(file.sub("#{File.dirname(@libraries_dir)}/", ''), file)
      end
    end

    puts "✅ Backed up #{files.size} files"
    backup_path
  end
end

# CLI
if __FILE__ == $PROGRAM_NAME
  LibraryBackup.new.backup
end
