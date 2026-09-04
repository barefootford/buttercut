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

  def install(dir, name)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n")
    File.chmod(0o755, path)
    path
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
end

# Real ffprobe against real files: the fixture mov has an audio track, a lavfi
# clip rendered with -an has none. Uses the ffmpeg/ffprobe MediaTools resolves for
# the suite (dependencies/ or PATH), like the contact-sheet specs do.
RSpec.describe MediaTools, '.audio_stream?' do
  let(:tmp) { Dir.mktmpdir('bc-audio-stream') }
  after { FileUtils.remove_entry(tmp) }

  it 'is true for a file with an audio stream' do
    expect(MediaTools.audio_stream?(File.join(__dir__, '../fixtures/media/MVI_0309_720p.mov'))).to be(true)
  end

  it 'is false for picture-only footage' do
    clip = File.join(tmp, 'drone.mp4')
    system(MediaTools.ffmpeg, '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=1:size=64x64:rate=10',
           '-an', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', clip, exception: true)

    expect(MediaTools.audio_stream?(clip)).to be(false)
  end

  # ffprobe can't read the file at all: don't guess "silent" and quietly skip
  # transcription — let whisperx run and report the real failure.
  it 'assumes audio when ffprobe cannot read the file' do
    expect(MediaTools.audio_stream?(File.join(tmp, 'missing.mov'))).to be(true)
  end
end

RSpec.describe MediaTools, '.whisperx' do
  let(:tmp) { Dir.mktmpdir('bc-whisperx') }
  after { FileUtils.remove_entry(tmp) }

  # The venv binary is preferred over anything on PATH so the job never runs
  # through a wrapper script — older ones reported exit 0 for every crash.
  it 'prefers the venv binary when it exists' do
    bin = File.join(tmp, 'whisperx')
    File.write(bin, "#!/bin/sh\n")
    File.chmod(0o755, bin)
    stub_const('MediaTools::WHISPERX_VENV_BIN', bin)

    expect(MediaTools.whisperx).to eq(bin)
  end

  it 'falls back to the bare name for installs without the standard venv' do
    stub_const('MediaTools::WHISPERX_VENV_BIN', File.join(tmp, 'absent'))

    expect(MediaTools.whisperx).to eq('whisperx')
  end
end
