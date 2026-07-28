# frozen_string_literal: true

require 'tmpdir'
require 'yaml'

# A throwaway libraries root plus helpers to write library.yaml fixtures —
# shared by the core and Pro Library specs.
RSpec.shared_context 'library sandbox' do
  let(:libraries_root) { @libraries_root }
  let(:library_name) { 'test-lib' }
  let(:library_dir) { File.join(libraries_root, library_name) }
  let(:library_yaml_path) { File.join(library_dir, 'library.yaml') }

  around do |example|
    Dir.mktmpdir('library-spec-') do |root|
      @libraries_root = root
      example.run
    end
  end

  before do
    stub_const('Library::LIBRARIES_ROOT', @libraries_root)
    allow($stdout).to receive(:puts)
  end

  def write_library(media:, name: library_name, **metadata)
    dir = File.join(libraries_root, name)
    FileUtils.mkdir_p(File.join(dir, 'transcripts'))
    FileUtils.mkdir_p(File.join(dir, 'contact_sheets'))
    FileUtils.mkdir_p(File.join(dir, 'summaries'))
    payload = metadata.transform_keys(&:to_s).merge('media' => media)
    File.write(File.join(dir, 'library.yaml'), payload.to_yaml)
    dir
  end

  # A video record: probed duration + the three video fields.
  def video_entry(filename, **overrides)
    {
      'path' => "/tmp/#{filename}",
      'duration' => '00:00:05',
      'transcript' => '',
      'contact_sheet' => '',
      'summary' => ''
    }.merge(overrides.transform_keys(&:to_s))
  end

  # An image record: no duration, no transcript/contact_sheet — just a summary.
  def image_entry(filename, **overrides)
    {
      'path' => "/tmp/#{filename}",
      'summary' => ''
    }.merge(overrides.transform_keys(&:to_s))
  end

  def touch(*paths)
    paths.each { |p| FileUtils.touch(p) }
  end

  def load_yaml
    YAML.safe_load_file(library_yaml_path)
  end
end
