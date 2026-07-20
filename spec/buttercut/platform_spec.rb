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

    it 'finds a bare-name executable on POSIX' do
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

  describe '.ffmpeg_filter_path' do
    it 'double-escapes a Windows drive colon so both ffmpeg parser levels survive' do
      expect(Platform.ffmpeg_filter_path('C:/repo/lib/buttercut/Arimo-Regular.ttf'))
        .to eq('C\\\\:/repo/lib/buttercut/Arimo-Regular.ttf')
    end

    it 'normalizes backslash separators to forward slashes' do
      expect(Platform.ffmpeg_filter_path('C:\\repo\\font.ttf')).to eq('C\\\\:/repo/font.ttf')
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
  end
end
