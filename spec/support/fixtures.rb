# frozen_string_literal: true

require 'yaml'
require 'digest'
require 'fileutils'

# Resolves the large binary test fixtures that live outside git (see
# spec/assets_manifest.yml). A clip is used from spec/assets/ when a local copy is
# present; otherwise it is downloaded from the manifest's base_url, checksum-verified,
# and cached into spec/assets/ for subsequent runs.
#
# On CI the spec/assets/ directory is restored/saved by actions/cache, so each clip
# is downloaded at most once per manifest revision.
module Fixtures
  ASSETS_DIR    = File.expand_path('../assets', __dir__)
  MANIFEST_PATH = File.expand_path('../assets_manifest.yml', __dir__)
  MANIFEST      = YAML.load_file(MANIFEST_PATH).freeze
  REPO_ROOT     = File.expand_path('../..', __dir__)

  class FixtureError < StandardError; end

  module_function

  # Absolute path to the named fixture, fetching it on first use if needed.
  def path(filename)
    entry = MANIFEST.fetch('files').fetch(filename) do
      raise FixtureError, "Unknown fixture #{filename.inspect} — add it to #{rel(MANIFEST_PATH)}"
    end
    local = File.join(ASSETS_DIR, filename)
    fetch!(filename, local, entry) unless present?(local, entry)
    local
  end

  # A local copy counts as present when it exists and its size matches the manifest.
  # Cheap gate on purpose — we don't re-hash multi-hundred-MB clips on every run; the
  # checksum is verified when a file is freshly downloaded.
  def present?(local, entry)
    File.exist?(local) && File.size(local) == entry['size']
  end

  def fetch!(filename, local, entry)
    base = base_url
    unless base
      raise FixtureError, <<~MSG.strip
        Fixture #{filename.inspect} is not in #{rel(ASSETS_DIR)} and no download location is set.
        Either drop the file there, or set base_url in #{rel(MANIFEST_PATH)}
        (or the BUTTERCUT_FIXTURES_BASE_URL env var) to the public fixtures bucket URL.
      MSG
    end

    url = "#{base}/#{filename}"
    FileUtils.mkdir_p(ASSETS_DIR)
    tmp = File.join(ASSETS_DIR, ".#{filename}.#{Process.pid}.part")

    begin
      warn "[fixtures] fetching #{filename} (#{entry['size']} bytes) from #{url}"
      ok = system('curl', '--fail', '--location', '--silent', '--show-error',
                  '--retry', '3', '--connect-timeout', '30',
                  '--output', tmp, url)
      raise FixtureError, "Download failed: #{url}" unless ok

      actual = Digest::SHA256.file(tmp).hexdigest
      unless actual == entry['sha256']
        raise FixtureError, "Checksum mismatch for #{filename}: expected #{entry['sha256']}, got #{actual}"
      end

      File.rename(tmp, local)
    ensure
      File.delete(tmp) if File.exist?(tmp)
    end
  end

  # Public read-only base URL. Resolution order:
  #   1. the BUTTERCUT_FIXTURES_BASE_URL env var (what CI and fresh clones use), then
  #   2. the manifest's base_url, which may be a literal URL or a ${ENV_VAR} reference.
  # The ${ENV_VAR} form keeps the bucket URL out of source: the manifest names the env
  # var, and the actual URL is supplied by the environment (in CI, a repo variable).
  # Returns nil when nothing is configured, which yields a helpful error in fetch!.
  def base_url
    from_env = ENV['BUTTERCUT_FIXTURES_BASE_URL']
    return from_env.strip.chomp('/') if from_env && !from_env.strip.empty?

    configured = MANIFEST['base_url']
    return nil unless configured.is_a?(String)
    configured = configured.strip
    return nil if configured.empty? || configured == 'REPLACE_ME'

    if (ref = configured[/\A\$\{?(\w+)\}?\z/, 1])
      val = ENV[ref]
      return val && !val.strip.empty? ? val.strip.chomp('/') : nil
    end

    configured.chomp('/')
  end

  # Path relative to the repo root, for friendlier error messages.
  def rel(absolute)
    absolute.sub("#{REPO_ROOT}/", '')
  end
end
