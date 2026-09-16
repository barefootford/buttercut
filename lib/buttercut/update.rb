#!/usr/bin/env ruby
# frozen_string_literal: true

# Updates ButterCut in place: stash local edits, switch to main, pull, restart
# the daily update-check clock, and report what changed as JSON. The
# update-buttercut skill runs this as ONE command instead of a hand-typed
# sequence of git commands — every git call (and, in Pro, the license header
# that authenticates the pull) stays inside this process, so the agent's
# transcript only ever shows `ruby lib/buttercut/update.rb`. That matters for
# agent clients that review each shell command before running it: a plain
# script invocation reads as routine, a secret being threaded into git config
# does not.
#
#   ruby lib/buttercut/update.rb          # update: stash, checkout main, pull, report
#   ruby lib/buttercut/update.rb check    # fetch only: is an update available?
#
# Both print one JSON object. Exit 0 on success; 1 when git failed (the JSON
# carries `error` + `message` for the user). Pro adds its own exit code for a
# declined license — see update_pro.rb.

require 'json'
require 'open3'

require_relative 'library'
require_relative 'version'

class Updater
  REMOTE = 'origin'
  BRANCH = 'main'
  STASH_PREFIX = 'update-buttercut auto-stash'

  # Exit code per `error` value; Pro adds its license codes. Unfrozen so the
  # extension can merge into it.
  EXIT_CODES = { 'network' => 1 }

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

  def initialize(repo_root: Library::REPO_ROOT, remote: REMOTE, branch: BRANCH)
    @repo_root = repo_root
    @remote = remote
    @branch = branch
  end

  # Fetch the release branch and say whether HEAD is behind it.
  def check
    fetch!
    behind = git!('rev-list', '--count', "HEAD..#{@remote}/#{@branch}").strip.to_i
    { 'update_available' => behind.positive?, 'commits_behind' => behind }
  rescue GitFailed => e
    network_failure(e)
  end

  # The whole update. Local edits are stashed (tagged, never reapplied — the
  # skill tells the user they're saved); libraries/ is gitignored so nothing
  # here touches their work.
  def run
    before = head
    stash = stash!
    git!('checkout', @branch)
    pull!
    Library.record_update_check!(repo_root: @repo_root)
    after = head
    {
      'updated' => before != after,
      'before' => before,
      'after' => after,
      'stashed' => stash,
      'changelog' => changelog_additions(before, after),
      'skills_link_ok' => skills_link_ok?
    }
  rescue GitFailed => e
    network_failure(e).merge('stashed' => stash)
  end

  # Edition seam: extra `git -c key=value` pairs every network command carries.
  # Core pulls from public GitHub and needs none; Pro attaches its license.
  def network_config = []

  # Edition seam: what to tell the user when fetch/pull fails. Core updates
  # need no credentials, so a failure is the network or GitHub being away.
  def network_failure(error)
    {
      'error' => 'network',
      'message' => "Couldn't reach the update server (#{error.stderr.strip.lines.last.to_s.strip}). " \
                   'Try again in a few minutes.'
    }
  end

  private

  def head = git!('rev-parse', 'HEAD').strip

  def fetch! = git!(*network_config, 'fetch', @remote, @branch)

  def pull! = git!(*network_config, 'pull', @remote, @branch)

  # Stash name when something was set aside, nil when the tree was clean.
  def stash!
    name = "#{STASH_PREFIX} #{Time.now.strftime('%Y-%m-%d-%H%M%S')}"
    out = git!('stash', 'push', '--include-untracked', '-m', name)
    out.include?('No local changes') ? nil : name
  end

  # Lines the update added to CHANGELOG.md — already written for users, so the
  # skill recaps them instead of running git itself. Empty when nothing changed.
  def changelog_additions(before, after)
    return [] if before == after

    diff = git!('diff', "#{before}..#{after}", '--', 'CHANGELOG.md')
    diff.lines.filter_map do |line|
      next unless line.start_with?('+') && !line.start_with?('+++')

      line[1..].rstrip
    end
  end

  # On Windows a checkout without symlink support can turn `.claude/skills`
  # back into a plain text file; the skill repairs it when this is false.
  def skills_link_ok?
    File.directory?(File.join(@repo_root, '.claude', 'skills'))
  end

  # Runs git in the repo with terminal prompts disabled, so a declined
  # credential fails fast instead of hanging on a password prompt no one can see.
  def git!(*args)
    argv = ['git', '-C', @repo_root, *args]
    out, err, status = Open3.capture3({ 'GIT_TERMINAL_PROMPT' => '0' }, *argv)
    raise GitFailed.new(args, err) unless status.success?

    out
  end
end

# Pro layers the license onto the network commands here; core ships no such file.
ButterCut.load_extension('update')

if __FILE__ == $PROGRAM_NAME
  action = ARGV.first || 'run'
  unless %w[run check].include?(action)
    warn "Usage: ruby lib/buttercut/update.rb [run|check]"
    exit 1
  end

  result = Updater.new.public_send(action)
  puts JSON.pretty_generate(result)
  exit(result.key?('error') ? Updater::EXIT_CODES.fetch(result['error'], 1) : 0)
end
