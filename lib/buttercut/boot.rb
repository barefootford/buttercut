#!/usr/bin/env ruby
# frozen_string_literal: true

# Ruby-version gate for every script the skills invoke directly.
#
# THIS FILE MUST STAY PARSEABLE BY macOS SYSTEM RUBY (2.6). No endless method
# definitions (`def x = y`), no pattern matching, no argument forwarding (`...`),
# nothing else 3.x-only. Same rule applies to the entry-point files that require
# it — see spec/buttercut/boot_spec.rb, which enforces both halves.
#
# Why the rule exists: Ruby parses an entire file before running line 1, so a
# version check written inside a file that itself uses 3.x syntax never gets to
# run. You get ~60 lines of `syntax error, unexpected '='` instead, which reads
# like a corrupt checkout. The check only works from a file the old parser can
# still read, which is what this one is.
#
# Why it re-execs instead of just complaining: on macOS this misfires even when
# the machine is set up correctly. `/etc/zprofile` runs `path_helper`, which
# rebuilds PATH with the system directories first — and it runs AFTER
# `~/.zshenv`, so mise's shims get demoted behind `/usr/bin` in any login shell.
# `ruby` is then 2.6 no matter what the setup skill wrote. Rather than hand that
# problem to the caller, find the real interpreter and hand off to it.

class ButterCut
  module Boot
    MINIMUM_RUBY = '3.0'

    # Set on the child before exec so a mis-resolving interpreter can't put us
    # in a re-exec loop: second time through we abort with a message instead.
    REEXEC_FLAG = 'BUTTERCUT_REEXEC'

    REPO_ROOT = File.expand_path('../..', __dir__)

    def self.ruby_ok?
      Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(MINIMUM_RUBY)
    end

    # Where mise puts the interpreters it installs. Globbed as a last resort
    # because these paths reach a Ruby directly: no mise binary, no config
    # resolution, and no trust prompt. `mise exec` refuses to run at all in a
    # checkout that hasn't been `mise trust`ed, which is exactly the kind of
    # half-configured machine that lands here in the first place.
    MISE_INSTALLS = '~/.local/share/mise/installs/ruby/*/bin/ruby'

    # Candidate ways to reach a Ruby 3, best first. The `ruby = ...` line in
    # .buttercut_env is what the setup skill recorded for this machine, so it
    # wins. `mise exec` comes next because it honours the version pinned in
    # .mise.toml. The bare interpreters are the backstop.
    def self.candidates
      recorded = recorded_ruby
      list = []
      list << recorded if recorded
      list << [File.expand_path('~/.local/bin/mise'), 'exec', '--', 'ruby']
      list << ['mise', 'exec', '--', 'ruby']
      list + installed_rubies
    end

    # Newest first, so a machine carrying several installs gets the best one.
    # The `3.3`/`3`/`latest` aliases mise keeps alongside real versions are
    # symlinks to the same interpreters, so duplicates here are harmless.
    def self.installed_rubies
      paths = Dir.glob(File.expand_path(MISE_INSTALLS))
      paths.sort_by { |path| version_key(path) }.reverse.map { |path| [path] }
    end

    # `.../installs/ruby/3.3.6/bin/ruby` sorts above `.../ruby/3.3/bin/ruby`,
    # and the non-numeric aliases (`latest`) sort last rather than raising.
    def self.version_key(path)
      dirname = path[%r{/ruby/([^/]+)/bin/ruby\z}, 1].to_s
      return Gem::Version.new('0') unless dirname =~ /\A\d+(\.\d+)*\z/

      Gem::Version.new(dirname)
    end

    def self.recorded_ruby
      path = File.join(REPO_ROOT, '.buttercut_env')
      return nil unless File.file?(path)

      line = File.readlines(path).find { |l| l =~ /\A\s*ruby\s*=/ }
      return nil if line.nil?

      argv = line.split('=', 2).last.to_s.strip.split(/\s+/)
      argv.empty? ? nil : argv
    end

    # Ask a candidate where its interpreter actually lives, and how old it is.
    #
    # The recorded invocation is usually `mise exec -- ruby`, which picks its
    # version from the .mise.toml nearest the WORKING DIRECTORY — run it from
    # somewhere outside the checkout and it happily hands back the same 2.6 we
    # are trying to escape. So the probe runs with cwd pinned to the repo root.
    # Pinning the probe rather than the real exec is deliberate: we want an
    # absolute interpreter path, which is cwd-independent, so the script itself
    # still runs in the caller's directory and relative path arguments survive.
    def self.probe(argv)
      # Required here, not at the top: this file loads on every single CLI
      # invocation, and open3 is only needed on the path where something is
      # already wrong.
      require 'open3'

      out, err, status = Open3.capture3(*argv, '-e', 'print RbConfig.ruby, " ", RUBY_VERSION',
                                       chdir: REPO_ROOT)
      unless status.success?
        note_failure(argv, err)
        return nil
      end

      path, version = out.split(' ', 2)
      return nil if path.nil? || version.nil? || path.empty?
      return nil unless File.executable?(path)
      return nil if Gem::Version.new(version.strip) < Gem::Version.new(MINIMUM_RUBY)

      path
    rescue StandardError => e
      # Candidate isn't installed, isn't executable, or died. Try the next one.
      note_failure(argv, e.message)
      nil
    end

    # Keep why each candidate was rejected. A candidate can fail for a reason
    # the caller can act on — an untrusted .mise.toml is the common one — and
    # "no Ruby found" on its own sends people hunting in the wrong place.
    def self.failures
      @failures ||= []
    end

    def self.note_failure(argv, message)
      text = message.to_s.strip
      failures << [argv.join(' '), text] unless text.empty?
    end

    def self.resolve
      candidates.each do |argv|
        found = probe(argv)
        return found if found
      end
      nil
    end

    def self.reexec!
      target = resolve
      abort(failure_message) if target.nil?

      ENV[REEXEC_FLAG] = '1'
      exec(target, $PROGRAM_NAME, *ARGV)
    end

    def self.failure_message
      <<~MESSAGE
        buttercut: needs Ruby #{MINIMUM_RUBY}+, but this shell is running #{RUBY_VERSION} (#{RbConfig.ruby})
        and no Ruby #{MINIMUM_RUBY}+ could be found to hand off to.

        This is a PATH/setup problem, not a bad checkout — re-cloning will not help.
        #{tried_section}
        To fix it, run the setup skill, or add mise's shims to ~/.zprofile:

          eval "$(mise activate --shims zsh)"

        ~/.zprofile is the file that matters on macOS: /etc/zprofile runs
        path_helper, which demotes anything ~/.zshenv prepended behind /usr/bin.
      MESSAGE
    end

    def self.tried_section
      return '' if failures.empty?

      lines = failures.map { |command, message| "  #{command}\n#{indent(salient_lines(message))}" }
      "\nTried:\n#{lines.join("\n")}\n"
    end

    # Tools are chatty on the way down. mise in particular leads with `[WARN]`
    # noise and puts the line that actually tells you what to do ("... are not
    # trusted. Trust them with `mise trust`") further along, so skipping
    # warnings is what makes this section worth printing.
    def self.salient_lines(message, limit = 2)
      all = message.to_s.lines.map(&:strip).reject(&:empty?)
      meaty = all.reject { |line| line =~ /\A(\[?WARN|mise WARN)/i }
      (meaty.empty? ? all : meaty).first(limit)
    end

    def self.indent(lines)
      lines.map { |line| "    #{line}" }.join("\n")
    end

    def self.call
      return if ruby_ok?

      if ENV[REEXEC_FLAG]
        abort(failure_message)
      else
        reexec!
      end
    end
  end
end

ButterCut::Boot.call
