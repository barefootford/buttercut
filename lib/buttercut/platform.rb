# frozen_string_literal: true

# One owner of OS detection and the OS-specific decisions ButterCut's Ruby layer
# needs, so the rest of lib/ never sniffs RUBY_PLATFORM or shells out to
# POSIX-only probes. Everything here avoids the shell: PATH lookups stat the
# filesystem and commands come back as argv arrays (no sh vs cmd.exe quoting).
#
# Two shapes, and feature code should only ever need these:
#
#   locators  (`windows_system_tar`, `powershell`, `find_tool`) return nil when
#             this platform can't provide the thing, so callers chain on nil.
#   intents   (`open_argv`, `keep_awake_argv`, `reveal_argv`) return argv for
#             "do the thing", already resolved for this OS.
#
# The payoff is that adding a platform-specific behavior means adding a method
# here, not an `if Platform.windows?` in a feature file. Outside this module,
# `windows?`/`mac?` should appear only where the OS is genuinely the subject
# (an editor that only ships for macOS), never to pick a command.
module Platform
  module_function

  # Wrapped so specs can stub one seam instead of RbConfig internals.
  def host_os = RbConfig::CONFIG['host_os']

  def windows? = host_os.match?(/mswin|mingw|cygwin/i)
  def mac? = host_os.match?(/darwin/i)

  # Fixed list rather than %PATHEXT% — covers every binary ButterCut cares about.
  WINDOWS_EXECUTABLE_EXTS = %w[.exe .com .bat .cmd].freeze

  # Filenames that could satisfy a command name here: on Windows a bare `ffmpeg`
  # on disk is really `ffmpeg.exe`, so extension variants are tried first.
  def executable_names(name)
    return [name] unless windows?
    return [name] if WINDOWS_EXECUTABLE_EXTS.include?(File.extname(name).downcase)

    WINDOWS_EXECUTABLE_EXTS.map { |ext| "#{name}#{ext}" } + [name]
  end

  # Full path of the first executable matching `name` inside `dir`, or nil.
  def find_executable(name, dir)
    executable_names(name)
      .map { |candidate| File.join(dir, candidate) }
      .find { |path| File.file?(path) && File.executable?(path) }
  end

  # The directories PATH names, in order. Windows PATH entries are sometimes
  # written with surrounding quotes ("C:\Program Files\Git\cmd") — File.join
  # would keep them and every lookup in that directory would miss.
  def path_dirs
    ENV.fetch(path_env_key, '').split(File::PATH_SEPARATOR)
       .map { |dir| dir.delete('"') }
       .reject(&:empty?)
  end

  # How the current environment actually spells PATH — Windows uses `Path`, and
  # a spawn env hash that introduces a second spelling can be the one the child
  # ignores. Anything overriding PATH for a subprocess should key off this.
  def path_env_key = ENV.keys.find { |key| key.casecmp?('PATH') } || 'PATH'

  # PATH lookup without a shell: full path of the first hit, or nil.
  def which(name)
    path_dirs.lazy.filter_map { |dir| find_executable(name, dir) }.first
  end

  def command_available?(name) = !which(name).nil?

  # The one tool-resolution ladder: first hit for `name` scanning `dirs` in
  # order, where the symbol :path stands for the PATH directories. A hit in one
  # of our own directories comes back as an absolute path; a hit on PATH comes
  # back as the bare name, left for the OS to resolve at exec time. nil when
  # it's nowhere — the caller decides whether that's fatal.
  #
  # Order is the caller's policy: ffmpeg is dependencies-first (ButterCut's own
  # static build wins), WhisperX is PATH-first (a system install wins over the
  # venv setup dropped in ~/.buttercut).
  def find_tool(name, *dirs)
    dirs.lazy
        .filter_map { |dir| dir == :path ? (name if command_available?(name)) : find_executable(name, dir) }
        .first
  end

  # argv that opens a file/folder/URL with the OS default handler; nil where
  # there's no reliable opener. The empty string fills `start`'s title slot.
  # No core caller yet — the Pro edition's preview server opens through these.
  def open_argv(target)
    return ['open', target] if mac?
    return ['cmd', '/c', 'start', '', target] if windows?

    nil
  end

  # Open `target` with the OS default handler; false (rather than raising) when
  # the platform has no opener, so callers can fall back to printing it.
  def launch(target)
    argv = open_argv(target)
    argv ? system(*argv) : false
  end

  # PowerShell has no `caffeinate`, so Windows gets a tiny script that holds
  # the wake request open for as long as it runs (see the file's own comments).
  KEEP_AWAKE_SCRIPT = File.expand_path('../../scripts/keep_awake.ps1', __dir__)

  # argv for a process that keeps the machine from idle-sleeping while it runs,
  # and stops mattering the moment it's killed. nil where we have no such
  # thing — callers should carry on rather than treat it as a failure.
  def keep_awake_argv
    return ['caffeinate', '-i'] if mac?
    return powershell_script_argv(KEEP_AWAKE_SCRIPT) if windows?

    nil
  end

  # argv that shows `path` to the user in their file manager, selected. Used
  # where opening the file itself would be wrong — an editor-bound XML that
  # Windows would hand to a browser, say.
  def reveal_argv(path)
    return ['open', '-R', path] if mac?
    return [system_root('explorer.exe'), "/select,#{backslashes(path)}"] if windows?

    nil
  end

  # argv that opens `path` with a named application. Only macOS can do this
  # meaningfully for ButterCut's exports; nil everywhere else.
  def open_with_app_argv(app, path)
    return ['open', '-a', app, path] if mac?

    nil
  end

  # Hardware decoder worth asking ffmpeg for on this machine. Optimistic is
  # fine: callers treat a decode failure as non-fatal and retry in software.
  def ffmpeg_hwaccel
    return 'videotoolbox' if mac?
    return 'd3d11va' if windows?

    nil
  end

  # Backslashed Windows input normalized to the forward-slash form ButterCut
  # stores and matches everywhere. No-op for POSIX paths.
  def forward_slashes(path) = path.tr('\\', '/')

  # The inverse, for the Windows-native programs that insist on it (Explorer
  # silently ignores a /select, argument written with forward slashes).
  def backslashes(path) = path.tr('/', '\\')

  # How many backslashes each character needs to reach ffmpeg intact, given the
  # two parsers it passes through on the way (the filtergraph description, then
  # the filter's own option list).
  #
  #   , ; [ ]  the filtergraph separators and label brackets. Only the first
  #            parser cares, so one escape, which it consumes.
  #   :        splits the option list, so it has to survive the filtergraph to
  #            reach the option parser — one escape per level. A single C\:
  #            truncates the value at the drive letter.
  #   '        opens a quoted run. Its escape has to survive the filtergraph
  #            too, and a backslash costs two on its own, so: \\ + \' = 3. Two
  #            leaves a bare quote at the filtergraph level, which then eats
  #            the rest of the chain.
  #
  # The counts are empirical — contact_sheet_spec runs each of these shapes
  # through real ffmpeg, because the failures are silent-ish and awful: both
  # C:/Users/O'Brien and a "shots, b-roll" folder are ordinary things to have.
  FFMPEG_PATH_ESCAPES = { ':' => 2, "'" => 3, ',' => 1, ';' => 1, '[' => 1, ']' => 1 }.freeze

  # Escape a path for use inside an ffmpeg filter argument (drawtext's
  # `fontfile=`, say). Separators are normalized first, so no backslash of our
  # own survives to be re-escaped.
  def ffmpeg_filter_path(path)
    forward_slashes(path)
      .gsub(/[:',;\[\]]/) { |char| ('\\' * FFMPEG_PATH_ESCAPES.fetch(char)) + char }
  end

  def system_root(*parts) = File.join(ENV.fetch('SystemRoot', 'C:/Windows'), *parts)
  def system32(*parts) = system_root('System32', *parts)

  # System32's bsdtar (ships with Windows 10 1803+). Unlike Git Bash's GNU tar
  # it can WRITE zip (`-a` infers the format from the suffix). nil off-Windows.
  def windows_system_tar
    return nil unless windows?

    tar = system32('tar.exe')
    File.exist?(tar) ? tar : nil
  end

  # Windows PowerShell 5.1's fixed home — on every Windows 10/11 install,
  # independent of PATH state. nil off-Windows.
  def powershell
    return nil unless windows?

    system32('WindowsPowerShell', 'v1.0', 'powershell.exe')
  end

  # argv that runs one PowerShell command; quote embedded values with ps_quote.
  # nil off-Windows, so callers chain on it instead of asking `windows?`.
  def powershell_argv(command)
    return nil unless powershell

    [powershell, '-NoProfile', '-Command', command]
  end

  # argv that runs a PowerShell *script file*. nil off-Windows.
  def powershell_script_argv(script_path)
    return nil unless powershell

    [powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script_path]
  end

  # PowerShell single-quoted string literal — quotes double to escape.
  def ps_quote(str) = "'#{str.gsub("'", "''")}'"
end
