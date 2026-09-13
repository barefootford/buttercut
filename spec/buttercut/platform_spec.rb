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
        original_path = ENV['PATH']
        ENV['PATH'] = dir
        example.run
      ensure
        ENV['PATH'] = original_path
      end
    end

    def install(name)
      path = File.join(@dir, name)
      File.write(path, "#!/bin/sh\n")
      File.chmod(0o755, path)
      path
    end

    it 'finds a bare-name executable on POSIX' do
      skip 'bare-name executables need a POSIX filesystem' if windows_host?
      on_linux!
      expected = install('ffmpeg')
      expect(Platform.find_executable('ffmpeg', @dir)).to eq(expected)
      expect(Platform.which('ffmpeg')).to eq(expected)
      expect(Platform.command_available?('ffmpeg')).to be(true)
    end

    it 'finds the .exe variant on Windows' do
      on_windows!
      expected = install('ffmpeg.exe')
      expect(Platform.find_executable('ffmpeg', @dir)).to eq(expected)
      expect(Platform.which('ffmpeg')).to eq(expected)
    end

    it 'misses a bare-name file when looking for a command on Windows' do
      on_windows!
      install('ffmpeg.exe')
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
        original = ENV['SystemRoot']
        ENV['SystemRoot'] = root
        begin
          expect(Platform.windows_system_tar).to eq(tar)
        ensure
          original.nil? ? ENV.delete('SystemRoot') : ENV['SystemRoot'] = original
        end
      end
    end
  end

  describe '.powershell' do
    it 'is nil off Windows' do
      on_linux!
      expect(Platform.powershell).to be_nil
    end

it 'points at the fixed Windows PowerShell 5.1 path when it exists' do
  on_windows!
  Dir.mktmpdir('bc-sysroot') do |root|
    home = File.join(root, 'System32', 'WindowsPowerShell', 'v1.0')
    FileUtils.mkdir_p(home)
    pwsh = File.join(home, 'powershell.exe')
    File.write(pwsh, '')
    original = ENV['SystemRoot']
    ENV['SystemRoot'] = root
    begin
      expect(Platform.powershell).to eq(pwsh)
    ensure
      original.nil? ? ENV.delete('SystemRoot') : ENV['SystemRoot'] = original
    end
  end
end

it 'is nil on Windows when PowerShell is missing' do
  on_windows!
  Dir.mktmpdir('bc-sysroot') do |root|
    original = ENV['SystemRoot']
    ENV['SystemRoot'] = root
    begin
      expect(Platform.powershell).to be_nil
    ensure
      original.nil? ? ENV.delete('SystemRoot') : ENV['SystemRoot'] = original
    end
  end
end
  end

  describe '.facts' do
    def uname(release:, machine:)
      { sysname: 'x', nodename: 'andrews-laptop', release: release, version: 'v', machine: machine }
    end

    it 'reports macOS by product version with a normalized architecture' do
      on_mac!
      allow(Etc).to receive(:uname).and_return(uname(release: '24.6.0', machine: 'arm64'))
      allow(File).to receive(:read).with(Platform::MAC_SYSTEM_VERSION_PLIST)
                                   .and_return("<key>ProductVersion</key>\n\t<string>15.6</string>")

      expect(Platform.facts).to eq('os' => 'macos', 'release' => '15.6', 'arch' => 'arm64', 'ruby' => RUBY_VERSION)
    end

    it 'falls back to the kernel release when the macOS version file is unreadable' do
      on_mac!
      allow(Etc).to receive(:uname).and_return(uname(release: '24.6.0', machine: 'x86_64'))
      allow(File).to receive(:read).with(Platform::MAC_SYSTEM_VERSION_PLIST).and_raise(Errno::ENOENT)

      expect(Platform.facts).to include('release' => '24.6.0', 'arch' => 'x86_64')
    end

    it 'reports Windows by build number and takes the architecture from the environment' do
      on_windows!
      allow(Etc).to receive(:uname).and_return(uname(release: '10.0.26100', machine: 'unknown'))
      stub_const('ENV', ENV.to_h.merge('PROCESSOR_ARCHITECTURE' => 'ARM64').tap { |e| e.delete('PROCESSOR_ARCHITEW6432') })

      expect(Platform.facts).to eq('os' => 'windows', 'release' => '10.0.26100', 'arch' => 'arm64',
                                   'ruby' => RUBY_VERSION)
    end

    it 'normalizes x64 spellings and never includes the hostname' do
      on_windows!
      allow(Etc).to receive(:uname).and_return(uname(release: '10.0.19045', machine: 'x64'))
      stub_const('ENV', ENV.to_h.merge('PROCESSOR_ARCHITECTURE' => 'AMD64').tap { |e| e.delete('PROCESSOR_ARCHITEW6432') })

      facts = Platform.facts
      expect(facts['arch']).to eq('x86_64')
      expect(facts.values.join).not_to include('andrews-laptop')
    end

    it 'calls everything else linux' do
      on_linux!
      allow(Etc).to receive(:uname).and_return(uname(release: '6.8.0', machine: 'aarch64'))

      expect(Platform.facts).to include('os' => 'linux', 'release' => '6.8.0', 'arch' => 'arm64')
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
