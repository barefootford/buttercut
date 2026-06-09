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
end
