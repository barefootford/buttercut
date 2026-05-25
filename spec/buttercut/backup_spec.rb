require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'yaml'
require_relative '../../lib/buttercut/backup_libraries'

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
      FileUtils.mkdir_p(File.join(lib_path, 'cuts'))

      File.write(
        File.join(lib_path, 'library.yaml'),
        YAML.dump({ 'library_name' => lib_name, 'videos' => [] })
      )
      File.write(File.join(lib_path, 'transcripts', 'video1_transcript.json'), '{"test": "data"}')
      File.write(File.join(lib_path, 'cuts', 'cut1.yaml'), 'test: cut')
    end
  end

  describe '#backup_all' do
    before { seed_libraries }

    context 'when Apple Archive (aa) is available' do
      before do
        allow_any_instance_of(LibraryBackup).to receive(:aa_available?).and_return(true)
      end

      it 'creates one timestamped .aar per library under <backups_dir>/<library>/' do
        results = LibraryBackup.new(temp_dir, backups_dir: backups_dir).backup_all

        expect(results.size).to eq(2)
        results.each do |path|
          expect(path).to match(%r{/library[12]/library[12]_\d{8}_\d{6}\.aar\z})
          expect(File.exist?(path)).to be true
        end

        lib1_archive = results.find { |p| p.include?('library1') }
        listing, _, status = Open3.capture3('aa', 'list', '-i', lib1_archive)
        expect(status).to be_success
        expect(listing).to include('library.yaml')
        expect(listing).to include('transcripts/video1_transcript.json')
        expect(listing).to include('cuts/cut1.yaml')
        expect(listing).not_to include('library2')
      end
    end

    context 'when Apple Archive is unavailable' do
      before do
        allow_any_instance_of(LibraryBackup).to receive(:aa_available?).and_return(false)
      end

      it 'creates one timestamped .zip per library under <backups_dir>/<library>/' do
        results = LibraryBackup.new(temp_dir, backups_dir: backups_dir).backup_all

        expect(results.size).to eq(2)
        results.each do |path|
          expect(path).to match(%r{/library[12]/library[12]_\d{8}_\d{6}\.zip\z})
          expect(File.exist?(path)).to be true
        end

        lib1_archive = results.find { |p| p.include?('library1') }
        listing, _, status = Open3.capture3('unzip', '-Z1', lib1_archive)
        expect(status).to be_success
        entries = listing.split("\n")
        expect(entries).to include('library1/library.yaml')
        expect(entries).to include('library1/transcripts/video1_transcript.json')
        expect(entries).to include('library1/cuts/cut1.yaml')
        expect(entries.none? { |e| e.start_with?('library2') }).to be true
      end
    end

    it 'returns [] when libraries directory does not exist' do
      FileUtils.rm_rf(libraries_dir)
      expect(LibraryBackup.new(temp_dir, backups_dir: backups_dir).backup_all).to eq([])
    end

    context 'legacy in-project backups/ cleanup' do
      let(:legacy_dir) { File.join(temp_dir, 'backups') }
      let(:external_dir) { File.join(temp_dir, 'external-backups') }

      before do
        allow_any_instance_of(LibraryBackup).to receive(:aa_available?).and_return(false)
        FileUtils.mkdir_p(legacy_dir)
        File.write(File.join(legacy_dir, 'libraries_old.zip'), 'stale')
      end

      it 'removes the legacy backups/ dir after a successful backup_all to an external location' do
        LibraryBackup.new(temp_dir, backups_dir: external_dir).backup_all
        expect(Dir.exist?(legacy_dir)).to be false
      end

      it 'leaves the legacy dir alone when backups_dir points at it' do
        LibraryBackup.new(temp_dir, backups_dir: legacy_dir).backup_all
        expect(Dir.exist?(legacy_dir)).to be true
      end

      it 'leaves the legacy dir alone for single-library backups' do
        LibraryBackup.new(temp_dir, backups_dir: external_dir).backup_library('library1')
        expect(Dir.exist?(legacy_dir)).to be true
      end
    end
  end

  describe '#backup_library' do
    before { seed_libraries }

    it 'backs up only the named library' do
      allow_any_instance_of(LibraryBackup).to receive(:aa_available?).and_return(false)
      result = LibraryBackup.new(temp_dir, backups_dir: backups_dir).backup_library('library1')

      expect(result).to match(%r{/library1/library1_\d{8}_\d{6}\.zip\z})
      expect(File.exist?(result)).to be true
      expect(Dir.exist?(File.join(backups_dir, 'library2'))).to be false
    end

    it 'returns nil when the library does not exist' do
      expect(LibraryBackup.new(temp_dir, backups_dir: backups_dir).backup_library('missing')).to be_nil
    end
  end

  describe '.resolve_backups_dir' do
    it 'uses the override when provided' do
      expect(LibraryBackup.resolve_backups_dir(project_root: temp_dir, override: '/tmp/x')).to eq('/tmp/x')
    end

    it 'reads backups_dir from libraries/settings.yaml when present' do
      File.write(File.join(libraries_dir, 'settings.yaml'), YAML.dump('backups_dir' => '/tmp/from-settings'))
      expect(LibraryBackup.resolve_backups_dir(project_root: temp_dir)).to eq('/tmp/from-settings')
    end

    it 'falls back to the default under ~/Documents when no override or setting' do
      expect(LibraryBackup.resolve_backups_dir(project_root: temp_dir))
        .to eq(File.join(Dir.home, 'Documents', 'buttercut-video-editor-backups'))
    end
  end
end
