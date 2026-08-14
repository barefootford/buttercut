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
    captured_env = nil
    allow(Open3).to receive(:capture2e) do |env, *|
      captured_env = env
      ['', instance_double(Process::Status, success?: true)]
    end
    allow(job).to receive(:prepare_transcript)

    job.perform

    expect(captured_env['PATH'].split(':').first).to eq(MediaTools::DEPENDENCIES_DIR)
    expect(captured_env['PATH']).to include(ENV.fetch('PATH'))
  end

  def stub_whisperx_failure(output)
    allow(MediaTools).to receive(:ffmpeg) # preflight only — keep the spec hermetic
    allow(Open3).to receive(:capture2e).and_return(
      [output, instance_double(Process::Status, success?: false, exitstatus: 1)]
    )
  end

  # A Python traceback means whisperx itself is broken (a stale venv), not the
  # clip — the error must point at the requirements.txt resync so any session
  # can self-heal, even one updated by an older skill that didn't sync the venv.
  it 'points at the venv resync when whisperx dies with a Python traceback' do
    stub_whisperx_failure(<<~OUTPUT)
      Traceback (most recent call last):
        File "whisperx/asr.py", line 16, in <module>
      AttributeError: module 'torchaudio' has no attribute 'AudioMetaData'
    OUTPUT

    expect { job.perform }.to raise_error do |error|
      expect(error.message).to match(/pip install .*-r requirements\.txt/)
      expect(error.message).to include('AudioMetaData') # the traceback tail rides along for diagnosis
    end
  end

  it 'raises the plain failure message when whisperx fails without a traceback' do
    stub_whisperx_failure("some ffmpeg decode noise\n")

    expect { job.perform }.to raise_error('whisperx failed for clip.mov (exit 1)')
  end
end
