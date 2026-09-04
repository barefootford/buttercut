require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/transcribe_job'

RSpec.describe TranscribeJob do
  let(:output_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(output_dir) }

  let(:job) do
    described_class.new(
      library_name: 'test-lib', clip: 'clip.mov',
      video_path: '/footage/clip.mov', output_dir: output_dir,
      language_code: 'en', whisper_model: 'small'
    )
  end

  let(:transcript_path) { File.join(output_dir, 'clip.json') }

  # Simulates one whisperx run: `writes_json` mirrors whether the real binary
  # left a transcript behind, which varies independently of the exit status.
  def stub_whisperx(output, success:, writes_json: false)
    allow(MediaTools).to receive(:ffmpeg) # preflight only — keep the spec hermetic
    allow(Open3).to receive(:capture2e) do
      File.write(transcript_path, '{"segments": []}') if writes_json
      [output, instance_double(Process::Status, success?: success, exitstatus: success ? 0 : 1)]
    end
  end

  # WhisperX resolves a bare `ffmpeg` from PATH internally, so the subprocess
  # must see dependencies/ first — the env equivalent of MediaTools' precedence.
  it 'runs whisperx with dependencies/ leading the subprocess PATH' do
    captured_env = nil
    allow(Open3).to receive(:capture2e) do |env, *|
      captured_env = env
      File.write(transcript_path, '{"segments": []}')
      ['', instance_double(Process::Status, success?: true)]
    end
    allow(job).to receive(:prepare_transcript)

    job.perform

    expect(captured_env['PATH'].split(':').first).to eq(MediaTools::DEPENDENCIES_DIR)
    expect(captured_env['PATH']).to include(ENV.fetch('PATH'))
  end

  # Silent-clip handling varies by whisperx version: some builds exit non-zero,
  # some exit 0 without writing any JSON. Both must land on the same rescue —
  # B-roll with no dialogue is normal footage, not an error.
  ['exits 0 without writing a transcript', 'exits non-zero'].each do |variant|
    it "rescues a silent clip when whisperx #{variant}" do
      stub_whisperx("No active speech found in audio\n", success: variant.start_with?('exits 0'))
      expect(job).not_to receive(:prepare_transcript)

      job.perform

      expect(JSON.parse(File.read(transcript_path)))
        .to include('_note' => 'no dialogue', 'segments' => [], 'word_segments' => [])
    end
  end

  it 'raises when whisperx exits 0 with no transcript and no no-speech notice' do
    stub_whisperx("some unrelated noise\n", success: true)

    expect { job.perform }.to raise_error("whisperx produced no transcript at #{transcript_path}")
  end

  # A Python traceback means whisperx itself is broken (a stale venv), not the
  # clip — the error must point at the requirements.txt resync so any session
  # can self-heal, even one updated by an older skill that didn't sync the venv.
  it 'points at the venv resync when whisperx dies with a Python traceback' do
    stub_whisperx(<<~OUTPUT, success: false)
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
    stub_whisperx("some ffmpeg decode noise\n", success: false)

    expect { job.perform }.to raise_error('whisperx failed for clip.mov (exit 1)')
  end
end
