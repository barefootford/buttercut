# frozen_string_literal: true

# One owner of OS detection and the OS-specific decisions ButterCut's Ruby layer
# needs, so the rest of lib/ never sniffs RUBY_PLATFORM or shells out to
# POSIX-only probes. Everything here avoids the shell: PATH lookups stat the
# filesystem and commands come back as argv arrays (no sh vs cmd.exe quoting).
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

  # PATH lookup without a shell: full path of the first hit, or nil.
  def which(name)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)
       .lazy.reject(&:empty?)
       .filter_map { |dir| find_executable(name, dir) }
       .first
  end

  def command_available?(name) = !which(name).nil?

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

  # Escape a path for use inside an ffmpeg filter argument. Two parser levels
  # (filtergraph, then filter options) each consume one escape, so a drive
  # colon needs C\\: — a single C\: still splits the option and truncates the
  # value at the drive letter. No-op for POSIX paths.
  def ffmpeg_filter_path(path)
    forward_slashes(path).gsub(':') { '\\\\:' }
  end

  def system32(*parts) = File.join(ENV.fetch('SystemRoot', 'C:/Windows'), 'System32', *parts)

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
  def powershell_argv(command)
    [powershell, '-NoProfile', '-Command', command]
  end

  # PowerShell single-quoted string literal — quotes double to escape.
  def ps_quote(str) = "'#{str.gsub("'", "''")}'"
end
