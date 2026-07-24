#!/usr/bin/env ruby
# frozen_string_literal: true

# Library Backup Utility
# Creates per-library, timestamped backups under <backups_dir>/<library>/.
# Uses Apple Archive (.aar) when the macOS `aa` CLI is available — hardware-
# accelerated on Apple Silicon, Finder handles double-click extract. Falls
# back to a .zip otherwise (`zip` CLI, or Windows' built-in tooling).

require 'fileutils'
require 'optparse'
require 'time'
require 'yaml'
require_relative 'platform'

class LibraryBackup
  DEFAULT_BACKUPS_DIR = File.join(Dir.home, 'Documents', 'buttercut-video-editor-backups')

  def self.resolve_backups_dir(project_root: Dir.pwd, override: nil)
    return File.expand_path(override) if override && !override.empty?

    settings_path = File.join(project_root, 'libraries', 'settings.yaml')
    if File.exist?(settings_path)
      settings = YAML.safe_load_file(settings_path) || {}
      configured = settings['backups_dir']
      return File.expand_path(configured) if configured && !configured.to_s.empty?
    end

    DEFAULT_BACKUPS_DIR
  end

  def initialize(project_root = Dir.pwd, backups_dir: nil)
    @project_root = project_root
    @libraries_dir = File.join(project_root, 'libraries')
    @backups_dir = backups_dir || self.class.resolve_backups_dir(project_root: project_root)
  end

  # Back up a single library by name. Returns the archive path or nil on failure.
  def backup_library(library_name)
    library_path = File.join(@libraries_dir, library_name)
    unless Dir.exist?(library_path)
      puts "Library not found: #{library_name}"
      return nil
    end

    dest_dir = File.join(@backups_dir, library_name)
    FileUtils.mkdir_p(dest_dir)
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    if aa_available?
      backup_with_apple_archive(library_name, library_path, dest_dir, timestamp)
    else
      backup_with_zip(library_name, dest_dir, timestamp)
    end
  end

  # Back up every library in libraries/. Returns an array of archive paths.
  def backup_all
    unless Dir.exist?(@libraries_dir)
      puts 'No libraries directory found'
      return []
    end

    results = library_names.map { |name| backup_library(name) }.compact
    cleanup_legacy_backups_dir if results.any?
    results
  end

  # Remove the legacy <project_root>/backups/ directory once current backups
  # are safely written to an external location.
  def cleanup_legacy_backups_dir
    legacy = File.join(@project_root, 'backups')
    return unless Dir.exist?(legacy)
    return if File.expand_path(@backups_dir) == File.expand_path(legacy)

    size_mb = legacy_dir_size_mb(legacy)
    puts "Removing legacy in-project backups dir (#{size_mb} MB): #{legacy}"
    FileUtils.rm_rf(legacy)
  end

  private

  def legacy_dir_size_mb(path)
    bytes = Dir.glob(File.join(path, '**', '*'), File::FNM_DOTMATCH)
               .reject { |p| File.directory?(p) }
               .sum { |p| File.size?(p) || 0 }
    (bytes / (1024.0 * 1024)).round
  end

  def library_names
    Dir.children(@libraries_dir).select do |entry|
      Dir.exist?(File.join(@libraries_dir, entry))
    end.sort
  end

  def aa_available?
    Platform.mac? && Platform.command_available?('aa')
  end

  def backup_with_apple_archive(library_name, library_path, dest_dir, timestamp)
    backup_path = File.join(dest_dir, "#{library_name}_#{timestamp}.aar")
    puts "Creating backup: #{backup_path}"
    return nil unless system('aa', 'archive', '-D', library_path, '-o', backup_path)

    puts 'Backup complete'
    backup_path
  end

  def backup_with_zip(library_name, dest_dir, timestamp)
    backup_path = File.join(dest_dir, "#{library_name}_#{timestamp}.zip")
    argv = zip_command(backup_path, library_name)
    unless argv
      puts 'No zip tool found (looked for zip, the Windows System32 tar.exe, and PowerShell) — backup not written'
      return nil
    end

    puts "Creating backup: #{backup_path}"
    success = Dir.chdir(@libraries_dir) do
      system(*argv)
    end
    return nil unless success

    puts 'Backup complete'
    backup_path
  end

  # argv (run from @libraries_dir) that zips the library folder into backup_path,
  # or nil when this machine has nothing that can write one. Each rung asks what
  # exists rather than which OS this is — Windows has no zip CLI, so it lands on
  # System32's bsdtar, and PowerShell only if even that is missing (both nil
  # off-Windows, which is what ends the ladder).
  def zip_command(backup_path, library_name)
    return ['zip', '-rq', backup_path, library_name] if Platform.command_available?('zip')

    if (bsdtar = Platform.windows_system_tar)
      return [bsdtar, '-a', '-cf', backup_path, library_name]
    end

    Platform.powershell_argv(
      "Compress-Archive -Force -LiteralPath #{Platform.ps_quote(library_name)} " \
      "-DestinationPath #{Platform.ps_quote(backup_path)}"
    )
  end
end

if __FILE__ == $PROGRAM_NAME
  override = nil
  library = nil
  OptionParser.new do |opts|
    opts.banner = 'Usage: backup_libraries.rb [--backups-dir DIR] [--library NAME]'
    opts.on('--backups-dir DIR', 'Directory to write backups into') { |d| override = d }
    opts.on('--library NAME', 'Back up only the named library (default: all libraries)') { |n| library = n }
  end.parse!

  backups_dir = LibraryBackup.resolve_backups_dir(override: override)
  backup = LibraryBackup.new(Dir.pwd, backups_dir: backups_dir)
  library ? backup.backup_library(library) : backup.backup_all
end
