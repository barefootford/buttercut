require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require_relative '../../lib/buttercut/platform'

RSpec.describe Platform do
  # host_os is the one seam Platform reads the OS from, so stubbing it lets the
  # Windows paths run under the POSIX test suite (and vice versa).
  def on_windows! = allow(Platform).to receive(:host_os).and_return('mingw32')
  def on_mac!     = allow(Platform).to receive(:host_os).and_return('darwin24')
  def on_linux!   = allow(Platform).to receive(:host_os).and_return('linux-gnu')

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    original.nil? ? ENV.delete(key) : ENV[key] = original
  end

  describe 'OS detection' do
    it 'recognizes Windows host_os strings' do
      on_windows!
      expect(Platform.windows?).to be(true)
      expect(Platform.mac?).to be(false)
    end

    it 'recognizes macOS host_os strings' do
      on_mac!
      expect(Platform.mac?).to be(true)
      expect(Platform.windows?).to be(false)
    end

    it 'treats Linux as neither' do
      on_linux!
      expect(Platform.windows?).to be(false)
      expect(Platform.mac?).to be(false)
    end
  end

  describe '.executable_names' do
    it 'returns just the name on POSIX' do
      on_mac!
      expect(Platform.executable_names('ffmpeg')).to eq(['ffmpeg'])
    end

    it 'tries the Windows executable extensions first on Windows' do
      on_windows!
      expect(Platform.executable_names('ffmpeg'))
        .to eq(%w[ffmpeg.exe ffmpeg.com ffmpeg.bat ffmpeg.cmd ffmpeg])
    end

    it 'leaves a name that already carries an executable extension alone' do
      on_windows!
      expect(Platform.executable_names('ffmpeg.exe')).to eq(['ffmpeg.exe'])
    end
  end

  describe '.find_executable / .which / .command_available?' do
    around do |example|
      Dir.mktmpdir('bc-platform') do |dir|
        @dir = dir
        with_env('PATH', dir) { example.run }
      end
    end

    # An extensionless file can't be executable on Windows, so this one is
    # about POSIX's own convention rather than about ButterCut.
    it 'finds a bare-name executable on POSIX', :posix_only do
      on_linux!
      expected = install(@dir, 'ffmpeg')
      expect(Platform.find_executable('ffmpeg', @dir)).to eq(expected)
      expect(Platform.which('ffmpeg')).to eq(expected)
      expect(Platform.command_available?('ffmpeg')).to be(true)
    end

    it 'finds the .exe variant on Windows' do
      on_windows!
      expected = install(@dir, 'ffmpeg.exe')
      expect(Platform.find_executable('ffmpeg', @dir)).to eq(expected)
      expect(Platform.which('ffmpeg')).to eq(expected)
    end

    it 'misses a bare-name file when looking for a command on Windows' do
      on_windows!
      install(@dir, 'ffmpeg.exe')
      expect(Platform.find_executable('ffprobe', @dir)).to be_nil
      expect(Platform.command_available?('definitely-not-a-real-tool')).to be(false)
    end

    # Windows PATH entries are sometimes written with surrounding quotes; a
    # File.join that keeps them misses every binary in that directory.
    it 'strips quotes from PATH entries' do
      on_windows!
      expected = install(@dir, 'ffmpeg.exe')
      with_env('PATH', "\"#{@dir}\"") do
        expect(Platform.path_dirs).to eq([@dir])
        expect(Platform.which('ffmpeg')).to eq(expected)
      end
    end
  end

  describe '.find_tool' do
    around do |example|
      Dir.mktmpdir('bc-find-tool') do |own_dir|
        Dir.mktmpdir('bc-find-tool-path') do |path_dir|
          @own_dir = own_dir
          @path_dir = path_dir
          with_env('PATH', path_dir) { example.run }
        end
      end
    end

    # No host_os stub in this block: `install` writes whatever counts as an
    # executable here, so these run against the real platform on both.

    # The bare name for a PATH hit, the absolute path for one of our own
    # directories — so callers can hand either straight to Open3.
    it 'returns the absolute path for a directory hit' do
      expected = install(@own_dir, 'ffmpeg')
      expect(Platform.find_tool('ffmpeg', @own_dir, :path)).to eq(expected)
    end

    it 'returns the bare name for a PATH hit' do
      install(@path_dir, 'ffmpeg')
      expect(Platform.find_tool('ffmpeg', @own_dir, :path)).to eq('ffmpeg')
    end

    it 'honors the caller-supplied order' do
      own = install(@own_dir, 'whisperx')
      install(@path_dir, 'whisperx')

      expect(Platform.find_tool('whisperx', @own_dir, :path)).to eq(own)
      expect(Platform.find_tool('whisperx', :path, @own_dir)).to eq('whisperx')
    end

    it 'is nil when the tool is nowhere' do
      expect(Platform.find_tool('definitely-not-a-real-tool', @own_dir, :path)).to be_nil
    end
  end

  describe '.path_env_key' do
    it 'reports the spelling the environment actually uses' do
      # Windows environments say `Path`; overriding the wrong spelling for a
      # subprocess is a coin flip over which one the child reads.
      original = ENV.to_h
      ENV.delete('PATH')
      ENV['Path'] = '/usr/bin'
      expect(Platform.path_env_key).to eq('Path')
    ensure
      ENV.replace(original)
    end
  end

  describe '.ffmpeg_hwaccel' do
    it 'is videotoolbox on macOS' do
      on_mac!
      expect(Platform.ffmpeg_hwaccel).to eq('videotoolbox')
    end

    it 'is d3d11va on Windows' do
      on_windows!
      expect(Platform.ffmpeg_hwaccel).to eq('d3d11va')
    end

    it 'is nil elsewhere' do
      on_linux!
      expect(Platform.ffmpeg_hwaccel).to be_nil
    end
  end

  # These lock the escape counts in place; contact_sheet_spec proves the counts
  # are the ones real ffmpeg actually wants.
  describe '.ffmpeg_filter_path' do
    it 'double-escapes a Windows drive colon so both ffmpeg parser levels survive' do
      expect(Platform.ffmpeg_filter_path('C:/repo/lib/buttercut/Arimo-Regular.ttf'))
        .to eq('C\\\\:/repo/lib/buttercut/Arimo-Regular.ttf')
    end

    it 'normalizes backslash separators to forward slashes' do
      expect(Platform.ffmpeg_filter_path('C:\\repo\\font.ttf')).to eq('C\\\\:/repo/font.ttf')
    end

    # Three, not two: the backslash that escapes the quote has to survive the
    # filtergraph parser itself, and a backslash costs two on its own.
    it 'triple-escapes an apostrophe so it never opens a quoted run' do
      expect(Platform.ffmpeg_filter_path("/Users/O'Brien/font.ttf"))
        .to eq("/Users/O\\\\\\'Brien/font.ttf")
    end

    it 'escapes the filtergraph separators and brackets once each' do
      expect(Platform.ffmpeg_filter_path('/shots, b-roll/take [2]/a;b/font.ttf'))
        .to eq('/shots\\, b-roll/take \\[2\\]/a\\;b/font.ttf')
    end

    it 'leaves POSIX paths untouched' do
      expect(Platform.ffmpeg_filter_path('/repo/font.ttf')).to eq('/repo/font.ttf')
    end
  end

  describe '.open_argv' do
    it 'uses open on macOS' do
      on_mac!
      expect(Platform.open_argv('/tmp/x.xml')).to eq(['open', '/tmp/x.xml'])
    end

    it 'uses cmd start with an empty title on Windows' do
      on_windows!
      expect(Platform.open_argv('C:/x.xml')).to eq(['cmd', '/c', 'start', '', 'C:/x.xml'])
    end

    it 'has no opener on Linux' do
      on_linux!
      expect(Platform.open_argv('/tmp/x.xml')).to be_nil
      expect(Platform.launch('/tmp/x.xml')).to be(false)
    end
  end

  describe '.windows_system_tar' do
    it 'is nil off Windows' do
      on_mac!
      expect(Platform.windows_system_tar).to be_nil
    end

    it 'points at System32 tar.exe when it exists' do
      on_windows!
      Dir.mktmpdir('bc-sysroot') do |root|
        FileUtils.mkdir_p(File.join(root, 'System32'))
        tar = File.join(root, 'System32', 'tar.exe')
        File.write(tar, '')
        with_env('SystemRoot', root) { expect(Platform.windows_system_tar).to eq(tar) }
      end
    end
  end

  describe '.powershell' do
    it 'is nil off Windows' do
      on_linux!
      expect(Platform.powershell).to be_nil
    end

    it 'returns the fixed Windows PowerShell 5.1 path on Windows' do
      on_windows!
      with_env('SystemRoot', 'C:/Windows') do
        expect(Platform.powershell)
          .to eq('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe')
      end
    end
  end

  describe '.powershell_argv / .ps_quote' do
    it 'builds a one-liner argv with PowerShell-quoted values' do
      allow(Platform).to receive(:powershell).and_return('C:/ps/powershell.exe')

      argv = Platform.powershell_argv("Write-Output #{Platform.ps_quote("it's")}")

      # Single quotes double to escape inside a PowerShell single-quoted literal.
      expect(argv).to eq(['C:/ps/powershell.exe', '-NoProfile', '-Command', "Write-Output 'it''s'"])
    end

    # nil rather than an argv with a nil head, so callers chain on it instead
    # of guarding with `windows?`.
    it 'is nil off Windows' do
      on_mac!
      expect(Platform.powershell_argv('Write-Output 1')).to be_nil
      expect(Platform.powershell_script_argv('C:/x.ps1')).to be_nil
    end
  end

  describe '.keep_awake_argv' do
    it 'uses caffeinate on macOS' do
      on_mac!
      expect(Platform.keep_awake_argv).to eq(['caffeinate', '-i'])
    end

    it 'runs the PowerShell helper script on Windows' do
      on_windows!
      argv = Platform.keep_awake_argv
      expect(argv.first).to end_with('powershell.exe')
      expect(argv.last).to eq(Platform::KEEP_AWAKE_SCRIPT)
    end

    it 'is nil where there is nothing to hold the machine awake' do
      on_linux!
      expect(Platform.keep_awake_argv).to be_nil
    end
  end

  describe '.reveal_argv / .open_with_app_argv' do
    it 'reveals in Finder on macOS' do
      on_mac!
      expect(Platform.reveal_argv('/tmp/cut.fcpxml')).to eq(['open', '-R', '/tmp/cut.fcpxml'])
    end

    # Explorer ignores a /select, argument written with forward slashes.
    it 'reveals in Explorer with a backslashed path on Windows' do
      on_windows!
      with_env('SystemRoot', 'C:/Windows') do
        expect(Platform.reveal_argv('C:/cuts/my cut.xml'))
          .to eq(['C:/Windows/explorer.exe', '/select,C:\\cuts\\my cut.xml'])
      end
    end

    it 'only opens with a named application on macOS' do
      on_mac!
      expect(Platform.open_with_app_argv('Final Cut Pro', '/tmp/c.fcpxml'))
        .to eq(['open', '-a', 'Final Cut Pro', '/tmp/c.fcpxml'])

      on_windows!
      expect(Platform.open_with_app_argv('Adobe Premiere Pro', 'C:/c.xml')).to be_nil
    end
  end
end
