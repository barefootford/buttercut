# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/update'

RSpec.describe Updater do
  # A bare "origin" plus two clones: `install` is the user's ButterCut, `dev`
  # pushes the release the install should pick up.
  around do |example|
    Dir.mktmpdir('updater-') do |root|
      @origin = File.join(root, 'origin.git')
      @install = File.join(root, 'install')
      @dev = File.join(root, 'dev')
      sh('git', 'init', '--bare', '-q', '--initial-branch=main', @origin)
      sh('git', 'clone', '-q', @origin, @dev)
      commit(@dev, 'CHANGELOG.md', "# Changelog\n\n## [Unreleased]\n", 'first')
      sh('git', '-C', @dev, 'push', '-q', 'origin', 'main')
      sh('git', 'clone', '-q', @origin, @install)
      example.run
    end
  end

  def sh(*argv)
    out, err, status = Open3.capture3(*argv)
    raise "#{argv.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def commit(repo, file, content, message)
    File.write(File.join(repo, file), content)
    sh('git', '-C', repo, 'add', file)
    sh('git', '-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', message)
  end

  def release(lines)
    commit(@dev, 'CHANGELOG.md', "# Changelog\n\n## [Unreleased]\n#{lines}", 'release')
    sh('git', '-C', @dev, 'push', '-q', 'origin', 'main')
  end

  let(:updater) { described_class.new(repo_root: @install) }
  let(:stamp) { File.join(@install, Library::UPDATE_CHECK_FILE) }

  describe '#check' do
    it 'reports up to date when nothing new is on origin' do
      expect(updater.check).to eq('update_available' => false, 'commits_behind' => 0)
    end

    it 'counts the commits the install is behind' do
      release("- one\n")
      expect(updater.check).to eq('update_available' => true, 'commits_behind' => 1)
    end
  end

  describe '#run' do
    it 'pulls the release, restarts the update clock, and returns the changelog additions' do
      release("- **Photos.** Stills in libraries.\n")
      result = updater.run

      expect(result['updated']).to be(true)
      expect(result['before']).not_to eq(result['after'])
      expect(result['after']).to eq(sh('git', '-C', @dev, 'rev-parse', 'HEAD').strip)
      expect(result['changelog']).to eq(['- **Photos.** Stills in libraries.'])
      expect(result['stashed']).to be_nil
      expect(File.exist?(stamp)).to be(true)
    end

    it 'is a quiet no-op when already current' do
      result = updater.run
      expect(result['updated']).to be(false)
      expect(result['changelog']).to eq([])
    end

    it 'stashes local edits (tracked and untracked) and gets off a side branch' do
      sh('git', '-C', @install, 'checkout', '-q', '-b', 'claude-experiment')
      File.write(File.join(@install, 'CHANGELOG.md'), 'scribbles')
      File.write(File.join(@install, 'notes.txt'), 'untracked')
      release("- two\n")

      result = updater.run

      expect(result['updated']).to be(true)
      expect(result['stashed']).to start_with(Updater::STASH_PREFIX)
      expect(sh('git', '-C', @install, 'rev-parse', '--abbrev-ref', 'HEAD').strip).to eq('main')
      expect(File.exist?(File.join(@install, 'notes.txt'))).to be(false)
      expect(sh('git', '-C', @install, 'stash', 'list')).to include(Updater::STASH_PREFIX)
    end

    it 'reports a network failure instead of raising when origin is unreachable' do
      sh('git', '-C', @install, 'remote', 'set-url', 'origin', File.join(@install, 'nowhere.git'))
      result = updater.run
      expect(result['error']).to eq('network')
      expect(result['message']).to include('Try again')
    end
  end

  describe 'CLI' do
    # The real script always targets the real checkout, so only the usage
    # guard is exercised here; the class specs above cover run/check.
    it 'rejects an unknown action with usage and exit 1' do
      script = File.expand_path('../../lib/buttercut/update.rb', __dir__)
      _out, err, status = Open3.capture3('ruby', script, 'bogus')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('Usage')
    end
  end

end
