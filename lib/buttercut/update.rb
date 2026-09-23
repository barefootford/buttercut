#!/usr/bin/env ruby
# frozen_string_literal: true

# Updates ButterCut in place (fetch, fast-forward main, sync dependencies) and
# prints one JSON report. It's a single command so agents that review each shell
# command, like Claude Code's auto mode, see a routine script call instead of git
# plumbing or Pro's license header. `check` only fetches; `finish` is internal.

require 'json'
require 'open3'
require 'rbconfig'

require_relative 'library'
require_relative 'platform'
require_relative 'version'

class Updater
  REMOTE = 'origin'
  BRANCH = 'main'
  STASH_PREFIX = 'update-buttercut auto-stash'
  WRAPPER = "#!/bin/bash\nexec \"$HOME/.buttercut/venv/bin/whisperx\" \"$@\"\n"
  PIP_ARGS = %w[install --only-binary :all: --no-binary antlr4-python3-runtime,docopt -r requirements.txt].freeze

  # Unfrozen: update_pro.rb merges its license codes in.
  EXIT_CODES = { 'network' => 1, 'local' => 1, 'unexpected' => 1 }

  class GitFailed < StandardError
    attr_reader :argv, :stderr

    def initialize(argv, stderr)
      @argv = argv
      @stderr = stderr.to_s
      super("git #{argv.join(' ')} failed: #{@stderr.strip}")
    end
  end

  def initialize(repo_root: Library::REPO_ROOT, buttercut_home: File.join(Dir.home, '.buttercut'),
                 remote: REMOTE, branch: BRANCH)
    @repo_root = repo_root
    @buttercut_home = buttercut_home
    @remote = remote
    @branch = branch
  end

  def check
    fetch!
    behind = commits_behind
    { 'update_available' => behind.positive?, 'commits_behind' => behind }
  rescue GitFailed => e
    network_failure(e)
  rescue StandardError => e
    unexpected_failure(e)
  end

  def run(sync_dependencies: true)
    begin
      fetch!
    rescue GitFailed => e
      return network_failure(e)
    end

    stash = nil
    before = git!('rev-parse', @branch).strip
    if commits_behind.positive? || !on_branch?
      stash = stash!
      git!('checkout', @branch)
      git!('merge', '--ff-only', "#{@remote}/#{@branch}")
    end
    Library.record_update_check!(repo_root: @repo_root)
    after = head
    result = {
      'updated' => before != after,
      'before' => before,
      'after' => after,
      'stashed' => stash,
      'changelog' => changelog_additions(before, after),
      'skills_link_ok' => skills_link_ok?
    }
    result.merge!(finish_install_from(before, after)) if sync_dependencies
    result
  rescue GitFailed => e
    local_failure(e).merge('stashed' => stash)
  rescue StandardError => e
    unexpected_failure(e).merge('stashed' => stash)
  end

  def finish_install
    {
      'dependencies' => {
        'bundle' => sync_bundle,
        'whisperx' => sync_whisperx,
        'whisperx_wrapper' => repair_whisperx_wrapper
      },
      'shell_ruby_ok' => shell_ruby_ok?
    }
  end

  # Edition seams: update_pro.rb overrides these to attach and interpret the license.
  def network_config = []

  def network_failure(error)
    {
      'error' => 'network',
      'message' => "Couldn't reach the update server (#{reason(error)}). Try again in a few minutes."
    }
  end

  def local_failure(error)
    {
      'error' => 'local',
      'message' => "The update was downloaded but couldn't be applied: git #{error.argv.first} failed (#{reason(error)})."
    }
  end

  def unexpected_failure(error)
    {
      'error' => 'unexpected',
      'message' => "The updater hit an internal error (#{error.class}: #{error.message})."
    }
  end

  private

  def head = git!('rev-parse', 'HEAD').strip

  def fetch! = git!('fetch', @remote, @branch, config: network_config)

  def commits_behind = git!('rev-list', '--count', "#{@branch}..#{@remote}/#{@branch}").strip.to_i

  def on_branch? = git!('rev-parse', '--abbrev-ref', 'HEAD').strip == @branch

  def dirty? = !git!('status', '--porcelain', '--untracked-files=all').empty?

  def stash!
    return nil unless dirty?

    name = "#{STASH_PREFIX} #{Time.now.strftime('%Y-%m-%d-%H%M%S')}"
    git!('stash', 'push', '--include-untracked', '-m', name)
    name
  end

  def changelog_additions(before, after)
    return [] if before == after

    diff = git!('diff', "#{before}..#{after}", '--', 'CHANGELOG.md')
    diff.lines.filter_map do |line|
      next unless line.start_with?('+') && !line.start_with?('+++')

      text = line[1..].rstrip
      text unless text.empty?
    end
  end

  # A Windows checkout without symlink support turns .claude/skills into a text file.
  def skills_link_ok?
    File.directory?(File.join(@repo_root, '.claude', 'skills'))
  end

  def reason(error)
    error.stderr.lines.map(&:strip).reject(&:empty?).last.to_s
  end

  # This process loaded the old update.rb before the merge, so let the freshly
  # pulled script run the dependency steps; fall back to ours if it can't.
  def finish_install_from(before, after)
    return finish_install if before == after

    script = File.join(@repo_root, 'lib', 'buttercut', 'update.rb')
    out, _err, status = Open3.capture3(RbConfig.ruby, script, 'finish', chdir: @repo_root)
    status.success? ? JSON.parse(out) : finish_install
  rescue JSON::ParserError, SystemCallError
    finish_install
  end

  def sync_bundle
    return 'skipped' unless File.file?(File.join(@repo_root, 'Gemfile'))

    bundle = Gem.bin_path('bundler', 'bundle')
    run_quietly(RbConfig.ruby, bundle, 'install', '--quiet')
  rescue Gem::Exception
    'failed'
  end

  def sync_whisperx
    pip = File.join(@buttercut_home, 'venv', Platform.windows? ? 'Scripts/pip.exe' : 'bin/pip')
    return 'skipped' unless File.file?(pip) && File.file?(File.join(@repo_root, 'requirements.txt'))

    run_quietly(pip, *PIP_ARGS)
  end

  # Older wrappers ended in `deactivate`, which exited 0 even when whisperx crashed.
  def repair_whisperx_wrapper
    return 'skipped' if Platform.windows?

    wrapper = File.join(@buttercut_home, 'whisperx')
    return 'skipped' unless File.file?(wrapper)
    return 'ok' unless File.readlines(wrapper).any? { |line| line.start_with?('deactivate') }

    File.write(wrapper, WRAPPER)
    File.chmod(0o755, wrapper)
    'repaired'
  rescue SystemCallError
    'failed'
  end

  # Pre-mid-2026 installs lack the ~/.zprofile line that keeps mise ahead of
  # path_helper, so login shells fall back to Apple's Ruby 2.6.
  def shell_ruby_ok?
    return nil unless Platform.mac?

    shell = ENV.fetch('SHELL', '/bin/zsh')
    return nil unless File.executable?(shell)

    series = Regexp.escape(pinned_ruby[/\d+\.\d+/])
    %w[-lc -c].all? do |flag|
      out, _err, status = Open3.capture3(shell, flag, 'ruby --version', chdir: @repo_root)
      status.success? && out.match?(/\bruby #{series}\./)
    end
  end

  # Not RUBY_VERSION: an update that bumps the pin leaves this process on the old Ruby.
  def pinned_ruby
    toml = File.join(@repo_root, '.mise.toml')
    pin = File.read(toml)[/^\s*ruby\s*=\s*"([^"]+)"/, 1] if File.file?(toml)
    pin || RUBY_VERSION
  end

  # Passed through git's environment, not `-c`, so Pro's license key never shows
  # in a process listing. Git older than 2.31 ignores these.
  def config_env(pairs)
    return {} if pairs.empty?

    base = ENV.fetch('GIT_CONFIG_COUNT', '0').to_i
    env = { 'GIT_CONFIG_COUNT' => (base + pairs.size).to_s }
    pairs.each_with_index do |(key, value), i|
      env["GIT_CONFIG_KEY_#{base + i}"] = key
      env["GIT_CONFIG_VALUE_#{base + i}"] = value
    end
    env
  end

  def run_quietly(*argv)
    _out, _err, status = Open3.capture3(*argv, chdir: @repo_root)
    status.success? ? 'ok' : 'failed'
  rescue SystemCallError
    'failed'
  end

  # No terminal prompts (a declined license fails fast) and English messages
  # (update_pro.rb matches on them).
  def git!(*args, config: [])
    argv = ['git', '-C', @repo_root, *args]
    env = { 'GIT_TERMINAL_PROMPT' => '0', 'LC_ALL' => 'C', 'LANGUAGE' => '' }.merge(config_env(config))
    out, err, status = Open3.capture3(env, *argv)
    raise GitFailed.new(args, err) unless status.success?

    out
  end
end

ButterCut.load_extension('update')

if __FILE__ == $PROGRAM_NAME
  action = ARGV.first || 'run'
  unless %w[run check finish].include?(action)
    warn 'Usage: ruby lib/buttercut/update.rb [run|check]'
    exit 1
  end

  updater = Updater.new
  result =
    begin
      action == 'finish' ? updater.finish_install : updater.public_send(action)
    rescue StandardError => e
      updater.unexpected_failure(e)
    end
  puts JSON.pretty_generate(result)
  exit(result.key?('error') ? Updater::EXIT_CODES.fetch(result['error'], 1) : 0)
end
