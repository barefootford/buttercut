require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'zip'
require_relative '../.claude/skills/backup-library/backup_libraries'

RSpec.describe LibraryBackup do
  let(:temp_dir) { Dir.mktmpdir('buttercut-backup-test') }
  let(:libraries_dir) { File.join(temp_dir, 'libraries') }
  let(:backups_dir) { File.join(temp_dir, 'backups') }

  before do
    FileUtils.mkdir_p(libraries_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#backup' do
    before do
      ['library1', 'library2'].each do |lib_name|
        lib_path = File.join(libraries_dir, lib_name)
        FileUtils.mkdir_p(lib_path)
        FileUtils.mkdir_p(File.join(lib_path, 'transcripts'))
        FileUtils.mkdir_p(File.join(lib_path, 'roughcuts'))

        File.write(
          File.join(lib_path, 'library.yaml'),
          YAML.dump({ 'library_name' => lib_name, 'videos' => [] })
        )

        File.write(File.join(lib_path, 'transcripts', 'video1_transcript.json'), '{"test": "data"}')
        File.write(File.join(lib_path, 'transcripts', 'video1_visual.json'), '{"test": "visual"}')
        File.write(File.join(lib_path, 'roughcuts', 'roughcut1.yaml'), 'test: roughcut')
      end
    end

    it 'creates a timestamped ZIP backup of all libraries' do
      backup = LibraryBackup.new(temp_dir)
      result = backup.backup

      expect(result).to match(/libraries_\d{8}_\d{6}\.zip/)
      expect(File.exist?(result)).to be true
    end

    it 'includes all library files in the backup' do
      backup = LibraryBackup.new(temp_dir)
      result = backup.backup

      Zip::File.open(result) do |zip|
        expect(zip.find_entry('libraries/library1/library.yaml')).not_to be_nil
        expect(zip.find_entry('libraries/library2/library.yaml')).not_to be_nil
        expect(zip.find_entry('libraries/library1/transcripts/video1_transcript.json')).not_to be_nil
        expect(zip.find_entry('libraries/library1/transcripts/video1_visual.json')).not_to be_nil
        expect(zip.find_entry('libraries/library1/roughcuts/roughcut1.yaml')).not_to be_nil
      end
    end

    it 'returns nil when libraries directory does not exist' do
      FileUtils.rm_rf(libraries_dir)
      backup = LibraryBackup.new(temp_dir)
      result = backup.backup

      expect(result).to be_nil
    end
  end
end
