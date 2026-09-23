#!/usr/bin/env ruby
# frozen_string_literal: true

# Updates ButterCut in place: fetch, stash local edits, switch to main,
# fast-forward, sync dependencies, restart the daily update-check clock, and
# report what changed as JSON. The update-buttercut skill runs this as ONE
# command instead of a hand-typed sequence of git, bundler, and pip commands —
# every call (and, in Pro, the license header that authenticates the fetch)
# stays inside this process, so the agent's transcript only ever shows
# `ruby lib/buttercut/update.rb`. That matters for agent clients that review
# each shell command before running it: a plain script invocation reads as
# routine, a secret being threaded into git config does not.
#
#   ruby lib/buttercut/update.rb          # update: fetch, stash, checkout main, fast-forward, sync deps, report
#   ruby lib/buttercut/update.rb check    # fetch only: is an update available?
#   ruby lib/buttercut/update.rb finish   # internal: the dependency sync, re-run by the freshly pulled code
#
# Each prints one JSON object. Exit 0 on success; 1 when the update failed
# (the JSON carries `error` + `message` for the user: `network` when the fetch
# failed, `local` when the install's own git state blocked the update,
# `unexpected` when the updater itself broke). Pro adds its own exit code for
# a declined license.

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

  # Exit code per `error` value; Pro adds its license codes. Unfrozen so the
  # extension can merge into it.
  EXIT_CODES = { 'network' => 1, 'local' => 1, 'unexpected' => 1 }

  # A git command that exited non-zero. Carries stderr so the edition seam can
  # tell an auth refusal from a dropped connection.
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

  # Fetch the release branch and say whether local main is behind it.
  def check
    fetch!
    behind = commits_behind
    { 'update_available' => behind.positive?, 'commits_behind' => behind }
  rescue GitFailed => e
    network_failure(e)
  rescue StandardError => e
    unexpected_failure(e)
  end

  # The whole update. The fetch is the only network step, so only its failure
  # is reported as `network`; anything after it is the install's own git state
  # (`local`). Local edits are stashed (tagged, never reapplied — the skill
  # tells the user they're saved) and the branch switched only when there is
  # something to apply, so a current install is left exactly as found — a
  # local main that is merely ahead of origin has nothing to apply.
  # libraries/ is gitignored, so nothing here touches the user's work.
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

  # The post-pull housekeeping the skill used to run by hand: bundler, the
  # WhisperX venv pinned by requirements.txt, an old whisperx wrapper that hid
  # crashes, and whether agent shells still resolve the right Ruby (macOS).
  # Nothing here fails the update — each step reports ok / failed / skipped.
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

  # Edition seam: extra git config `[key, value]` pairs every network command
  # carries. Core pulls from public GitHub and needs none; Pro attaches its
  # license.
  def network_config = []

  # Edition seam: what to tell the user when the fetch fails. Core updates
  # need no credentials, so a failure is the network or GitHub being away.
  def network_failure(error)
    {
      'error' => 'network',
      'message' => "Couldn't reach the update server (#{reason(error)}). Try again in a few minutes."
    }
  end

  # A git step after the fetch failed: a diverged local main, a merge that
  # isn't a fast-forward, a checkout something is blocking. Waiting won't fix
  # it, so the message carries git's own words for whoever untangles it.
  def local_failure(error)
    {
      'error' => 'local',
      'message' => "The update was downloaded but couldn't be applied: git #{error.argv.first} failed (#{reason(error)})."
    }
  end

  # Anything that isn't git refusing a step is a bug in the updater itself.
  # The JSON still comes out, so the skill can tell the user and offer a bug
  # report instead of showing a stack trace.
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

  # Stash name when something was set aside, nil when the tree was clean.
  def stash!
    return nil unless dirty?

    name = "#{STASH_PREFIX} #{Time.now.strftime('%Y-%m-%d-%H%M%S')}"
    git!('stash', 'push', '--include-untracked', '-m', name)
    name
  end

  # Lines the update added to CHANGELOG.md — already written for users, so the
  # skill recaps them instead of running git itself. Empty when nothing changed.
  def changelog_additions(before, after)
    return [] if before == after

    diff = git!('diff', "#{before}..#{after}", '--', 'CHANGELOG.md')
    diff.lines.filter_map do |line|
      next unless line.start_with?('+') && !line.start_with?('+++')

      text = line[1..].rstrip
      text unless text.empty?
    end
  end

  # On Windows a checkout without symlink support can turn `.claude/skills`
  # back into a plain text file; the skill repairs it when this is false.
  def skills_link_ok?
    File.directory?(File.join(@repo_root, '.claude', 'skills'))
  end

  # Last line of git's stderr that says something, for the user's message.
  def reason(error)
    error.stderr.lines.map(&:strip).reject(&:empty?).last.to_s
  end

  # This process loaded update.rb before the merge, so once HEAD has moved its
  # copy of the dependency steps is the old release's. Hand them to the
  # freshly pulled script instead; fall back to the in-memory steps when that
  # can't run (a crash, output that isn't JSON).
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

  # The venv predates the standard layout when it's missing — that machine's
  # transcription setup lives wherever .buttercut_env points, so leave it be.
  def sync_whisperx
    pip = File.join(@buttercut_home, 'venv', Platform.windows? ? 'Scripts/pip.exe' : 'bin/pip')
    return 'skipped' unless File.file?(pip) && File.file?(File.join(@repo_root, 'requirements.txt'))

    run_quietly(pip, *PIP_ARGS)
  end

  # An older macOS wrapper ended in `deactivate`, which reported exit 0 even
  # when whisperx crashed. Windows installs have no wrapper.
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

  # macOS only: installs set up before mid-2026 lack the ~/.zprofile line that
  # keeps mise's shims ahead of path_helper, so login shells (`zsh -lc`, how
  # some agent clients run commands) fall back to Apple's Ruby 2.6. nil when
  # the check doesn't apply (Windows, or no login shell to ask).
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

  # The Ruby the checkout pins in .mise.toml — what agent shells should
  # resolve. Not RUBY_VERSION: an update that bumps the pin leaves this
  # process on the old Ruby while the shells already see the new one.
  def pinned_ruby
    toml = File.join(@repo_root, '.mise.toml')
    pin = File.read(toml)[/^\s*ruby\s*=\s*"([^"]+)"/, 1] if File.file?(toml)
    pin || RUBY_VERSION
  end

  # Config pairs as git's GIT_CONFIG_COUNT / GIT_CONFIG_KEY_n /
  # GIT_CONFIG_VALUE_n environment rather than `-c` arguments: Pro's pairs
  # carry the license key, and arguments show up in any process listing.
  # Numbered after pairs the parent environment already set, so those still
  # apply. Git older than 2.31 ignores these and falls back to the headers the
  # installer persisted in .git/config.
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

  # Runs git in the repo with terminal prompts disabled, so a declined
  # credential fails fast instead of hanging on a password prompt no one can
  # see, and with messages pinned to English so the edition seam can read them.
  def git!(*args, config: [])
    argv = ['git', '-C', @repo_root, *args]
    env = { 'GIT_TERMINAL_PROMPT' => '0', 'LC_ALL' => 'C', 'LANGUAGE' => '' }.merge(config_env(config))
    out, err, status = Open3.capture3(env, *argv)
    raise GitFailed.new(args, err) unless status.success?

    out
  end
end

# Pro layers the license onto the network commands here; core ships no such file.
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
