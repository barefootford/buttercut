# frozen_string_literal: true

# One owner of OS detection and the OS-specific decisions ButterCut's Ruby layer
# needs, so the rest of lib/ never sniffs RUBY_PLATFORM or shells out to
# POSIX-only probes. Everything here avoids the shell: PATH lookups stat the
# filesystem and commands come back as argv arrays (no sh vs cmd.exe quoting).
require 'etc'

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
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
      next if dir.empty?

      found = find_executable(name, dir)
      return found if found
    end
    nil
  end

  def command_available?(name) = !which(name).nil?

  # argv that opens a file/folder/URL with the OS default handler; nil where
  # there's no reliable opener. The empty string fills `start`'s title slot.
  def open_argv(target)
    return ['open', target] if mac?
    return ['cmd', '/c', 'start', '', target] if windows?

    nil
  end

  # Open `target` with the OS default handler; false (rather than raising) when
  # the platform has no opener, so callers can fall back to printing it.
  # What a bug report says about the machine: enough to tell a Windows 10 x64
  # box from an arm64 Mac, and nothing that identifies the person (no hostname,
  # no username — Etc.uname's nodename stays out on purpose).
  def facts
    uname = Etc.uname
    {
      'os' => windows? ? 'windows' : (mac? ? 'macos' : 'linux'),
      'release' => os_release(uname),
      'arch' => arch(uname),
      'ruby' => RUBY_VERSION
    }
  end

  MAC_SYSTEM_VERSION_PLIST = '/System/Library/CoreServices/SystemVersion.plist'
  ARCH_ALIASES = { 'x64' => 'x86_64', 'amd64' => 'x86_64', 'aarch64' => 'arm64' }.freeze

  # The version a person would recognize: macOS 15.6 rather than the Darwin
  # kernel's 24.6.0; on Windows, major.minor.build (10.0.26100 is 11 24H2).
  def os_release(uname = Etc.uname)
    if mac?
      product = File.read(MAC_SYSTEM_VERSION_PLIST)[%r{<key>ProductVersion</key>\s*<string>([^<]+)</string>}, 1]
      return product if product
    end
    uname[:release]
  rescue SystemCallError
    uname[:release]
  end

  # Normalized to x86_64 / arm64. Windows Ruby's uname reports arm64 machines as
  # "unknown", so the environment's own architecture variable wins there (the
  # WOW64 one first, so a 32-bit Ruby still names the real machine).
  def arch(uname = Etc.uname)
    machine = uname[:machine]
    machine = ENV['PROCESSOR_ARCHITEW6432'] || ENV['PROCESSOR_ARCHITECTURE'] || machine if windows?
    machine = machine.to_s.downcase
    ARCH_ALIASES.fetch(machine, machine)
  end

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

  # Escape a path for use inside an ffmpeg filter argument. Two parser levels
  # (filtergraph, then filter options) each consume one escape, so a drive
  # colon needs C\\: — a single C\: still splits the option and truncates the
  # value at the drive letter. No-op for POSIX paths.
  def ffmpeg_filter_path(path)
    path.tr('\\', '/').gsub(':') { '\\\\:' }
  end

  # System32's bsdtar (ships with Windows 10 1803+). Unlike Git Bash's GNU tar
  # it can WRITE zip (`-a` infers the format from the suffix). nil off-Windows.
  def windows_system_tar
    return nil unless windows?

    tar = File.join(ENV.fetch('SystemRoot', 'C:/Windows'), 'System32', 'tar.exe')
    File.exist?(tar) ? tar : nil
  end

  # Windows PowerShell 5.1's fixed home — on every Windows 10/11 install,
  # independent of PATH state. nil off-Windows, and nil when a locked-down
  # install has removed it, so callers fall through to their next option.
  def powershell
    return nil unless windows?

    pwsh = File.join(ENV.fetch('SystemRoot', 'C:/Windows'), 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    File.exist?(pwsh) ? pwsh : nil
  end

  # argv that runs one PowerShell command; quote embedded values with ps_quote.
  def powershell_argv(command)
    [powershell, '-NoProfile', '-Command', command]
  end

  # PowerShell single-quoted string literal — quotes double to escape.
  def ps_quote(str) = "'#{str.gsub("'", "''")}'"
end
