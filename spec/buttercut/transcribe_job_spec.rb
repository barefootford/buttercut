require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/transcribe_job'

RSpec.describe TranscribeJob do
  let(:output_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(output_dir) }

  # The clip's audio stream is probed with ffprobe before whisperx runs; the
  # specs below fake footage paths, so answer "has audio" unless a spec says
  # otherwise. The ffmpeg preflight is stubbed too, to keep the spec hermetic.
  before do
    allow(MediaTools).to receive(:audio_stream?).and_return(true)
    allow(MediaTools).to receive(:ffmpeg)
  end

  let(:job) do
    described_class.new(
      library_name: 'test-lib', clip: 'clip.mov',
      video_path: '/footage/clip.mov', output_dir: output_dir,
      language_code: 'en', whisper_model: 'small'
    )
  end

  SPOKEN = '{"segments": [{"start": 0.0, "end": 1.0, "text": "hello"}], "language": "en"}'.freeze
  SILENT = '{"segments": [], "language": "en"}'.freeze

  # The fake whisperx writes `<basename>.json` into whatever --output_dir it
  # was given, exactly as the real binary does.
  def stub_whisperx(json: SPOKEN, output: '')
    allow(Open3).to receive(:capture2e) do |env, *cmd|
      whisper_out = cmd[cmd.index('--output_dir') + 1]
      File.write(File.join(whisper_out, 'clip.json'), json) if json
      @captured_env = env
      @captured_cmd = cmd
      [output, instance_double(Process::Status, success?: true)]
    end
  end

  def stub_whisperx_failure(output)
    allow(Open3).to receive(:capture2e).and_return(
      [output, instance_double(Process::Status, success?: false, exitstatus: 1)]
    )
  end

  def transcript = JSON.parse(File.read(File.join(output_dir, 'clip.json')))

  def expect_no_dialogue_transcript
    expect(transcript).to include('_note' => 'no dialogue', 'segments' => [], 'video_path' => '/footage/clip.mov')
  end

  # WhisperX resolves a bare `ffmpeg` from PATH internally, so the subprocess
  # must see dependencies/ first — the env equivalent of MediaTools' precedence.
  it 'runs whisperx with dependencies/ leading the subprocess PATH' do
    stub_whisperx
    allow(job).to receive(:prepare_transcript)

    job.perform

    expect(@captured_env['PATH'].split(':').first).to eq(MediaTools::DEPENDENCIES_DIR)
    expect(@captured_env['PATH']).to include(ENV.fetch('PATH'))
  end

  it 'runs the whisperx binary MediaTools resolves, not whatever is on PATH' do
    allow(MediaTools).to receive(:whisperx).and_return('/venv/bin/whisperx')
    stub_whisperx
    allow(job).to receive(:prepare_transcript)

    job.perform

    expect(@captured_cmd.first).to eq('/venv/bin/whisperx')
  end

  it 'keeps a transcript with dialogue and hands it to prepare_transcript' do
    stub_whisperx
    expect(job).to receive(:prepare_transcript)

    job.perform

    expect(transcript['segments'].first['text']).to eq('hello')
  end

  # Picture-only cameras (drone bodies, action cams) have no audio stream at
  # all. whisperx can't decode what isn't there, so the job doesn't ask it to.
  it 'writes the no-dialogue transcript without running whisperx when the clip has no audio stream' do
    allow(MediaTools).to receive(:audio_stream?).with('/footage/clip.mov').and_return(false)
    expect(Open3).not_to receive(:capture2e)
    expect(job).not_to receive(:prepare_transcript)

    job.perform

    expect_no_dialogue_transcript
  end

  # whisperx 3.8+ handles a silent audio stream itself: it logs the no-speech
  # warning but exits 0 with {"segments": []}. That gets the same no-dialogue
  # note as a clip with no audio stream, so silence looks the same on disk.
  it 'normalizes an empty whisperx transcript to the no-dialogue transcript' do
    stub_whisperx(json: SILENT, output: "WARNING - No active speech found in audio\n")
    expect(job).not_to receive(:prepare_transcript)

    job.perform

    expect_no_dialogue_transcript
  end

  it 'rescues a no-speech clip when an older whisperx exits non-zero without writing anything' do
    stub_whisperx_failure("WARNING - No active speech found in audio\n")

    job.perform

    expect_no_dialogue_transcript
  end

  it 'rescues a no-speech clip when whisperx exits 0 without writing anything' do
    stub_whisperx(json: nil, output: "WARNING - No active speech found in audio\n")

    job.perform

    expect_no_dialogue_transcript
  end

  # Reported from the field and not reproduced: exit 0, no file, no no-speech
  # warning. The message has to carry whisperx's output — it's all we'll get.
  it 'raises with the whisperx output when it exits 0 with no transcript and no explanation' do
    stub_whisperx(json: nil, output: "something odd happened\n")

    expect { job.perform }.to raise_error do |error|
      expect(error.message).to include('exited 0 but produced no transcript')
      expect(error.message).to include('something odd happened')
    end
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

  # whisperx's load_audio raises "Failed to load audio" — as a traceback — when
  # ffmpeg can't decode the stream ffprobe reported. That's the footage, and
  # the message must not send the user off to reinstall WhisperX.
  it 'blames the footage, not the install, when whisperx cannot decode the audio' do
    stub_whisperx_failure(<<~OUTPUT)
      Traceback (most recent call last):
        File "whisperx/audio.py", line 63, in load_audio
      RuntimeError: Failed to load audio: Output file does not contain any stream
    OUTPUT

    expect { job.perform }.to raise_error do |error|
      expect(error.message).to include("couldn't decode the audio in clip.mov")
      expect(error.message).not_to include('pip install')
      expect(error.message).to include('does not contain any stream')
    end
  end

  # The wrapper script older installs run whisperx through ends in
  # `deactivate`, so the shell reports 0 for every crash. Neither report
  # below may depend on the exit status.
  it 'still diagnoses a stale install when the traceback arrives with exit 0' do
    stub_whisperx(json: nil, output: "Traceback (most recent call last):\nAttributeError: module 'torchaudio' has no attribute 'AudioMetaData'\n")

    expect { job.perform }.to raise_error(/pip install .*-r requirements\.txt/)
  end

  it 'still blames the footage when the decode failure arrives with exit 0' do
    stub_whisperx(json: nil, output: "Traceback (most recent call last):\nRuntimeError: Failed to load audio: Output file does not contain any stream\n")

    expect { job.perform }.to raise_error(/couldn't decode the audio in clip.mov/)
  end

  it 'raises the plain failure message when whisperx fails without a traceback' do
    stub_whisperx_failure("some ffmpeg decode noise\n")

    expect { job.perform }.to raise_error('whisperx failed for clip.mov (exit 1)')
  end
end
