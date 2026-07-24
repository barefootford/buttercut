require 'spec_helper'
require_relative '../../lib/buttercut/transcribe_job'

RSpec.describe TranscribeJob do
  let(:job) do
    described_class.new(
      library_name: 'test-lib', clip: 'clip.mov',
      video_path: '/footage/clip.mov', output_dir: '/tmp/out',
      language_code: 'en', whisper_model: 'small'
    )
  end

  # WhisperX resolves a bare `ffmpeg` from PATH internally, so the subprocess
  # must see dependencies/ first — the env equivalent of MediaTools' precedence.
  it 'runs whisperx with dependencies/ leading the subprocess PATH' do
    allow(described_class).to receive(:whisperx_command).and_return('whisperx')
    captured_env = nil
    allow(Open3).to receive(:capture2e) do |env, *|
      captured_env = env
      ['', instance_double(Process::Status, success?: true)]
    end
    allow(job).to receive(:prepare_transcript)

    job.perform

    # Exactly one PATH key, spelled the way this environment spells it —
    # Windows says `Path`, and handing the child a second `PATH` beside it is
    # a coin flip over which one it reads.
    keys = captured_env.keys.select { |key| key.casecmp?('PATH') }
    expect(keys.size).to eq(1)

    path = captured_env.fetch(keys.first)
    expect(path.split(File::PATH_SEPARATOR).first).to eq(MediaTools::DEPENDENCIES_DIR)
    expect(path).to include(ENV.fetch(keys.first))
  end

  describe '.whisperx_command' do
    it 'prefers a whisperx already on PATH' do
      allow(Platform).to receive(:command_available?).with('whisperx').and_return(true)

      expect(described_class.whisperx_command).to eq('whisperx')
    end

    it 'falls back to the ~/.buttercut venv entry point when PATH has none' do
      allow(Platform).to receive(:command_available?).with('whisperx').and_return(false)
      venv_bin = described_class::WHISPERX_FALLBACK_DIRS.find { |dir| dir.end_with?('venv/bin') }
      fallback = File.join(venv_bin, 'whisperx')
      allow(Platform).to receive(:find_executable).and_return(nil)
      allow(Platform).to receive(:find_executable).with('whisperx', venv_bin).and_return(fallback)

      expect(described_class.whisperx_command).to eq(fallback)
    end

    it 'raises a setup-skill error when whisperx is nowhere' do
      allow(Platform).to receive(:command_available?).with('whisperx').and_return(false)
      allow(Platform).to receive(:find_executable).and_return(nil)

      expect { described_class.whisperx_command }.to raise_error(MediaTools::MissingBinary, /setup skill/)
    end
  end

  it 'surfaces the tail of whisperx output when the run fails' do
    allow(described_class).to receive(:whisperx_command).and_return('whisperx')
    allow(Open3).to receive(:capture2e)
      .and_return(["Traceback (most recent call last):\nSomeError: model download failed\n",
                   instance_double(Process::Status, success?: false, exitstatus: 1)])

    expect { job.perform }.to raise_error(/exit 1.*model download failed/m)
  end
end
