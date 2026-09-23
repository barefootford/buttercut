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
      @home = File.join(root, 'buttercut-home')
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
    FileUtils.mkdir_p(File.dirname(File.join(repo, file)))
    File.write(File.join(repo, file), content)
    sh('git', '-C', repo, 'add', file)
    sh('git', '-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', message)
  end

  def release(lines)
    commit(@dev, 'CHANGELOG.md', "# Changelog\n\n## [Unreleased]\n#{lines}", 'release')
    sh('git', '-C', @dev, 'push', '-q', 'origin', 'main')
  end

  def branch(repo) = sh('git', '-C', repo, 'rev-parse', '--abbrev-ref', 'HEAD').strip

  let(:updater) { described_class.new(repo_root: @install, buttercut_home: @home) }
  let(:stamp) { File.join(@install, Library::UPDATE_CHECK_FILE) }
  # The dependency sync shells out to bundler and pip; the git plumbing is
  # what these examples exercise.
  let(:result) { updater.run(sync_dependencies: false) }

  describe '#check' do
    it 'reports up to date when nothing new is on origin' do
      expect(updater.check).to eq('update_available' => false, 'commits_behind' => 0)
    end

    it 'counts the commits the install is behind' do
      release("- one\n")
      expect(updater.check).to eq('update_available' => true, 'commits_behind' => 1)
    end

    it 'measures main, not whatever branch the install is parked on' do
      sh('git', '-C', @install, 'checkout', '-q', '-b', 'claude-experiment')
      commit(@install, 'notes.txt', 'experiment', 'side commit')
      expect(updater.check).to eq('update_available' => false, 'commits_behind' => 0)
    end
  end

  describe '#run' do
    it 'pulls the release, restarts the update clock, and returns the changelog additions' do
      release("- **Photos.** Stills in libraries.\n\n")

      expect(result['updated']).to be(true)
      expect(result['before']).not_to eq(result['after'])
      expect(result['after']).to eq(sh('git', '-C', @dev, 'rev-parse', 'HEAD').strip)
      expect(result['changelog']).to eq(['- **Photos.** Stills in libraries.'])
      expect(result['stashed']).to be_nil
      expect(result).not_to have_key('dependencies')
      expect(File.exist?(stamp)).to be(true)
    end

    it 'is a quiet no-op when already current' do
      expect(result['updated']).to be(false)
      expect(result['changelog']).to eq([])
    end

    it 'leaves local edits alone when there is nothing to apply' do
      File.write(File.join(@install, 'notes.txt'), 'in progress')

      expect(result['updated']).to be(false)
      expect(result['stashed']).to be_nil
      expect(File.read(File.join(@install, 'notes.txt'))).to eq('in progress')
    end

    it 'leaves local edits alone when main is ahead of origin but not behind' do
      commit(@install, 'notes.txt', 'local fix', 'local commit')
      File.write(File.join(@install, 'CHANGELOG.md'), 'scribbles')

      expect(result['updated']).to be(false)
      expect(result['stashed']).to be_nil
      expect(File.read(File.join(@install, 'CHANGELOG.md'))).to eq('scribbles')
      expect(sh('git', '-C', @install, 'stash', 'list')).to be_empty
    end

    it 'stashes local edits (tracked and untracked) and gets off a side branch' do
      sh('git', '-C', @install, 'checkout', '-q', '-b', 'claude-experiment')
      File.write(File.join(@install, 'CHANGELOG.md'), 'scribbles')
      File.write(File.join(@install, 'notes.txt'), 'untracked')
      release("- two\n")

      expect(result['updated']).to be(true)
      expect(result['stashed']).to start_with(Updater::STASH_PREFIX)
      expect(branch(@install)).to eq('main')
      expect(File.exist?(File.join(@install, 'notes.txt'))).to be(false)
      expect(sh('git', '-C', @install, 'stash', 'list')).to include(Updater::STASH_PREFIX)
    end

    it 'returns to main from a side branch without claiming an update' do
      sh('git', '-C', @install, 'checkout', '-q', '-b', 'claude-experiment')
      commit(@install, 'notes.txt', 'experiment', 'side commit')

      expect(result['updated']).to be(false)
      expect(result['changelog']).to eq([])
      expect(result['stashed']).to be_nil
      expect(branch(@install)).to eq('main')
    end

    it 'reports a network failure, touching nothing, when origin is unreachable' do
      sh('git', '-C', @install, 'remote', 'set-url', 'origin', File.join(@install, 'nowhere.git'))
      File.write(File.join(@install, 'notes.txt'), 'in progress')

      expect(result['error']).to eq('network')
      expect(result['message']).to include('Try again')
      expect(result).not_to have_key('stashed')
      expect(File.read(File.join(@install, 'notes.txt'))).to eq('in progress')
      expect(File.exist?(stamp)).to be(false)
    end

    it 'reports a local failure, not the network, when main has diverged' do
      commit(@install, 'notes.txt', 'local fix', 'local commit')
      File.write(File.join(@install, 'scratch.txt'), 'in progress')
      release("- three\n")

      expect(result['error']).to eq('local')
      expect(result['message']).to include('git merge failed')
      expect(result['message']).not_to include('Try again')
      expect(result['stashed']).to start_with(Updater::STASH_PREFIX)
      expect(Updater::EXIT_CODES[result['error']]).to eq(1)
    end

    it 'reports an unexpected failure as JSON, keeping the stash name, when a non-git step raises' do
      allow(Library).to receive(:record_update_check!).and_raise(Errno::EACCES, 'update stamp')
      File.write(File.join(@install, 'notes.txt'), 'in progress')
      release("- four\n")

      expect(result['error']).to eq('unexpected')
      expect(result['message']).to include('Permission denied')
      expect(result['stashed']).to start_with(Updater::STASH_PREFIX)
      expect(Updater::EXIT_CODES[result['error']]).to eq(1)
    end

    context 'with the dependency sync' do
      let(:result) { updater.run }

      it 'hands the sync to the freshly pulled updater once the code has moved' do
        commit(@dev, 'lib/buttercut/update.rb',
               %(require "json"\nputs JSON.generate("dependencies" => { "bundle" => "from-release" }, "argv" => ARGV)\n),
               'new updater')
        release("- five\n")

        expect(result['dependencies']).to eq('bundle' => 'from-release')
        expect(result['argv']).to eq(['finish'])
      end

      it 'falls back to its own sync when the pulled updater fails' do
        commit(@dev, 'lib/buttercut/update.rb', "exit 1\n", 'broken updater')
        release("- six\n")

        expect(result['dependencies']).to include('bundle' => 'skipped', 'whisperx' => 'skipped')
      end
    end
  end

  describe '#finish_install' do
    let(:wrapper) { File.join(@home, 'whisperx') }

    before { FileUtils.mkdir_p(@home) }

    it 'skips bundler and pip when the install has neither a Gemfile nor a venv' do
      deps = updater.finish_install['dependencies']
      expect(deps).to include('bundle' => 'skipped', 'whisperx' => 'skipped', 'whisperx_wrapper' => 'skipped')
    end

    it 'rewrites the old whisperx wrapper that swallowed crashes' do
      skip 'macOS-only wrapper' if Platform.windows?
      File.write(wrapper, "#!/bin/bash\nsource venv/bin/activate\nwhisperx \"$@\"\ndeactivate\n")

      expect(updater.finish_install['dependencies']['whisperx_wrapper']).to eq('repaired')
      expect(File.read(wrapper)).to eq(Updater::WRAPPER)
      expect(File.executable?(wrapper)).to be(true)
    end

    it 'leaves a current wrapper alone' do
      skip 'macOS-only wrapper' if Platform.windows?
      File.write(wrapper, Updater::WRAPPER)
      expect(updater.finish_install['dependencies']['whisperx_wrapper']).to eq('ok')
    end

    it 'measures agent shells against the Ruby the checkout pins, not the one running the updater' do
      skip 'macOS-only check' unless Platform.mac?
      File.write(File.join(@install, '.mise.toml'), %([tools]\nruby = "9.9.1"\n))
      shell_status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3).with(anything, anything, 'ruby --version', chdir: @install)
                                        .and_return(["ruby 9.9.1 (2027-01-01) [arm64-darwin25]\n", '', shell_status])

      expect(updater.finish_install['shell_ruby_ok']).to be(true)
    end
  end

  describe 'CLI' do
    # The real script always targets the real checkout, so only the usage
    # guard is exercised here; the class specs above cover run/check.
    it 'rejects an unknown action with usage and exit 1' do
      script = File.expand_path('../../lib/buttercut/update.rb', __dir__)
      _out, err, status = Open3.capture3(RbConfig.ruby, script, 'bogus')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('Usage')
    end
  end
end
