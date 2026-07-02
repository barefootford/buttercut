# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'stringio'

# Builds a throwaway on-disk library + cut YAML for the Export specs. Export
# resolves `libraries/<name>/library.yaml` relative to the working directory,
# so the sandbox chdirs into a temp dir shaped like a real ButterCut install.
module ExportSandbox
  MEDIA_DIR = File.expand_path('../fixtures/media', __dir__)

  def fixture_media(filename) = File.join(MEDIA_DIR, filename)

  # Yields [relative cut path, absolute output path] from inside the sandbox.
  def within_export_sandbox(cut:, media:, library: 'export-sandbox')
    Dir.mktmpdir do |dir|
      cuts_dir = File.join(dir, 'libraries', library, 'cuts')
      FileUtils.mkdir_p(cuts_dir)
      File.write(File.join(dir, 'libraries', library, 'library.yaml'),
                 { 'media' => media.map { |path| { 'path' => path } } }.to_yaml)
      File.write(File.join(cuts_dir, 'cut.yaml'), cut.to_yaml)
      Dir.chdir(dir) do
        yield File.join('libraries', library, 'cuts', 'cut.yaml'), File.join(dir, 'output.xml')
      end
    end
  end

  # Export reports skipped clips with `warn`; capture them for assertion.
  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end
end

RSpec.configure { |config| config.include ExportSandbox }
