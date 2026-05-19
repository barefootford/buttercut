require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'yaml'
require_relative '../skills/backup-library/backup_libraries'

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

  def seed_libraries
    %w[library1 library2].each do |lib_name|
      lib_path = File.join(libraries_dir, lib_name)
      FileUtils.mkdir_p(File.join(lib_path, 'transcripts'))
      FileUtils.mkdir_p(File.join(lib_path, 'roughcuts'))

      File.write(
        File.join(lib_path, 'library.yaml'),
        YAML.dump({ 'library_name' => lib_name, 'videos' => [] })
      )
      File.write(File.join(lib_path, 'transcripts', 'video1_transcript.json'), '{"test": "data"}')
      File.write(File.join(lib_path, 'roughcuts', 'roughcut1.yaml'), 'test: roughcut')
    end
  end

  describe '#backup' do
    before { seed_libraries }

    context 'when Apple Archive (aa) is available' do
      before do
        allow_any_instance_of(LibraryBackup).to receive(:aa_available?).and_return(true)
      end

      it 'creates a timestamped .aar backup with all library files' do
        result = LibraryBackup.new(temp_dir).backup

        expect(result).to match(/libraries_\d{8}_\d{6}\.aar/)
        expect(File.exist?(result)).to be true

        listing, _, status = Open3.capture3('aa', 'list', '-i', result)
        expect(status).to be_success
        expect(listing).to include('libraries/library1/library.yaml')
        expect(listing).to include('libraries/library2/library.yaml')
        expect(listing).to include('libraries/library1/transcripts/video1_transcript.json')
        expect(listing).to include('libraries/library1/roughcuts/roughcut1.yaml')
      end
    end

    context 'when Apple Archive is unavailable' do
      before do
        allow_any_instance_of(LibraryBackup).to receive(:aa_available?).and_return(false)
      end

      it 'creates a timestamped .zip backup with all library files' do
        result = LibraryBackup.new(temp_dir).backup

        expect(result).to match(/libraries_\d{8}_\d{6}\.zip/)
        expect(File.exist?(result)).to be true

        listing, _, status = Open3.capture3('unzip', '-Z1', result)
        expect(status).to be_success
        entries = listing.split("\n")
        expect(entries).to include('libraries/library1/library.yaml')
        expect(entries).to include('libraries/library2/library.yaml')
        expect(entries).to include('libraries/library1/transcripts/video1_transcript.json')
        expect(entries).to include('libraries/library1/roughcuts/roughcut1.yaml')
      end
    end

    it 'returns nil when libraries directory does not exist' do
      FileUtils.rm_rf(libraries_dir)
      expect(LibraryBackup.new(temp_dir).backup).to be_nil
    end
  end
end
