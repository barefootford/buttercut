require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require_relative '../../lib/buttercut/media_tools'

RSpec.describe MediaTools do
  before do
    @root = Dir.mktmpdir('bc-media-tools')
    @deps_dir = File.join(@root, 'dependencies')
    @path_dir = File.join(@root, 'bin')
    Dir.mkdir(@deps_dir)
    Dir.mkdir(@path_dir)
    stub_const('MediaTools::DEPENDENCIES_DIR', @deps_dir)

    @original_path = ENV['PATH']
    ENV['PATH'] = @path_dir
  end

  after do
    ENV['PATH'] = @original_path
    FileUtils.remove_entry(@root)
  end

  it 'prefers an executable in dependencies/ over PATH' do
    local = install(@deps_dir, 'ffmpeg')
    install(@path_dir, 'ffmpeg')

    expect(MediaTools.ffmpeg).to eq(local)
  end

  it 'falls back to the bare name when the binary is only on PATH' do
    install(@path_dir, 'ffprobe')

    expect(MediaTools.ffprobe).to eq('ffprobe')
  end

  it 'raises MissingBinary pointing at setup when the binary is nowhere' do
    expect { MediaTools.ffmpeg }
      .to raise_error(MediaTools::MissingBinary, /ffmpeg.*setup skill/)
  end

  it 'ignores a non-executable file in dependencies/' do
    File.write(File.join(@deps_dir, 'ffmpeg'), '')
    install(@path_dir, 'ffmpeg')

    expect(MediaTools.ffmpeg).to eq('ffmpeg')
  end

  context 'on Windows' do
    before { allow(Platform).to receive(:host_os).and_return('mingw32') }

    it 'resolves the .exe variant from dependencies/' do
      exe = install(@deps_dir, 'ffmpeg.exe')

      expect(MediaTools.ffmpeg).to eq(exe)
    end

    it 'falls back to the bare name when only ffprobe.exe is on PATH' do
      install(@path_dir, 'ffprobe.exe')

      expect(MediaTools.ffprobe).to eq('ffprobe')
    end
  end
end
