#!/usr/bin/env ruby
# frozen_string_literal: true

# Hold off idle sleep while ButterCut processes footage, without the calling
# skill needing to know how this machine does that (`caffeinate` on macOS, a
# SetThreadExecutionState loop under PowerShell on Windows).
#
#   PID=$(ruby lib/buttercut/keep_awake.rb start)
#   ruby lib/buttercut/keep_awake.rb stop "$PID"
#
# `start` prints one PID and nothing else, so it can be captured directly — and
# because it comes back through the agent's own tool output rather than a shell
# variable, it survives between steps even though shell state doesn't.
#
# Both commands exit 0 even when there was nothing to do. Failing to hold sleep
# off is never a reason to stop processing footage, so nothing here raises.
#
# The helper is spawned detached and given its own deadline (see MAX_SECONDS),
# so a session that dies before calling `stop` costs the user a few hours of a
# machine that won't idle-sleep, not a machine that never sleeps again.

require_relative 'platform'

module KeepAwake
  module_function

  # Longer than any real footage run, short enough that a leaked helper heals
  # itself the same day. macOS takes it as an argument; the PowerShell script
  # carries its own matching deadline.
  MAX_SECONDS = 12 * 60 * 60

  # Spawn the helper detached and return its PID, or nil when this platform has
  # no keep-awake mechanism (or the tool that provides it isn't installed).
  def start
    argv = Platform.keep_awake_argv
    return nil unless argv

    argv += ['-t', MAX_SECONDS.to_s] if argv.first == 'caffeinate'
    pid = Process.spawn(*argv, out: File::NULL, err: File::NULL)
    Process.detach(pid)
    pid
  rescue SystemCallError
    nil
  end

  # Stop a helper started earlier. Forgiving on purpose — an empty, malformed
  # or already-dead PID is a no-op, since this runs in cleanup positions where
  # raising would bury whatever actually went wrong.
  def stop(pid)
    pid = Integer(pid.to_s.strip, exception: false)
    return false unless pid

    Process.kill('KILL', pid)
    true
  rescue SystemCallError
    false
  end
end

if __FILE__ == $PROGRAM_NAME
  case ARGV.first
  when 'start'
    pid = KeepAwake.start
    puts pid if pid
  when 'stop'
    KeepAwake.stop(ARGV[1])
  else
    warn 'Usage: ruby keep_awake.rb start | stop <pid>'
    exit 1
  end
end
