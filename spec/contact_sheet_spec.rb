require_relative '../.claude/skills/detect-scenes/contact_sheet'

RSpec.describe ContactSheet do
  describe '.interval_for_duration' do
    it 'returns 5s for short clips (<=60s)' do
      expect(described_class.interval_for_duration(40)).to eq(5)
      expect(described_class.interval_for_duration(60)).to eq(5)
    end

    it 'returns 10s for 1-3 minute clips' do
      expect(described_class.interval_for_duration(120)).to eq(10)
      expect(described_class.interval_for_duration(180)).to eq(10)
    end

    it 'returns 15s for 3-5 minute clips' do
      expect(described_class.interval_for_duration(200)).to eq(15)
      expect(described_class.interval_for_duration(300)).to eq(15)
    end

    it 'returns 20s for clips over 5 minutes' do
      expect(described_class.interval_for_duration(600)).to eq(20)
      expect(described_class.interval_for_duration(1200)).to eq(20)
    end
  end

  describe '.grid_dimensions' do
    it 'calculates grid for 12 frames as 4x3' do
      cols, rows = described_class.grid_dimensions(12)
      expect(cols).to eq(4)
      expect(rows).to eq(3)
    end

    it 'calculates grid for 20 frames as 5x4' do
      cols, rows = described_class.grid_dimensions(20)
      expect(cols).to eq(5)
      expect(rows).to eq(4)
    end

    it 'calculates grid for 6 frames as 3x2' do
      cols, rows = described_class.grid_dimensions(6)
      expect(cols).to eq(3)
      expect(rows).to eq(2)
    end

    it 'handles single frame' do
      cols, rows = described_class.grid_dimensions(1)
      expect(cols).to eq(1)
      expect(rows).to eq(1)
    end
  end

  describe '.build_ffmpeg_command' do
    before do
      allow(described_class).to receive(:gpu_available?).and_return(false)
    end

    it 'builds correct command for full video' do
      cmd = described_class.build_ffmpeg_command(
        '/tmp/video.mp4', '/tmp/sheet.jpg',
        interval: 10, cols: 4, rows: 3
      )
      expect(cmd).to include('-i', '/tmp/video.mp4')
      expect(cmd).to include('-vf', "fps=1/10,scale=#{ContactSheet::THUMB_WIDTH}:#{ContactSheet::THUMB_HEIGHT},tile=4x3")
      expect(cmd).to include('-frames:v', '1', '-q:v', '3')
      expect(cmd).not_to include('-hwaccel')
    end

    it 'includes GPU acceleration when available' do
      allow(described_class).to receive(:gpu_available?).and_return(true)
      cmd = described_class.build_ffmpeg_command(
        '/tmp/video.mp4', '/tmp/sheet.jpg',
        interval: 10, cols: 4, rows: 3
      )
      expect(cmd).to include('-hwaccel', 'cuda')
    end

    it 'applies start and end time for windowed mode' do
      cmd = described_class.build_ffmpeg_command(
        '/tmp/video.mp4', '/tmp/sheet.jpg',
        interval: 2, cols: 3, rows: 2,
        start_time: 45.0, end_time: 60.0
      )
      expect(cmd).to include('-ss', '45.0')
      expect(cmd).to include('-t', '15.0')
    end
  end

  describe '.generate' do
    before do
      allow(described_class).to receive(:gpu_available?).and_return(false)
      allow(described_class).to receive(:video_duration).and_return(120.0)
      allow(described_class).to receive(:system).and_return(true)
    end

    it 'uses adaptive interval for full video' do
      result = described_class.generate('/tmp/video.mp4', output_path: '/tmp/sheet.jpg')
      expect(result[:interval]).to eq(10) # 120s -> 10s interval
      expect(result[:frame_count]).to eq(12)
      expect(result[:success]).to be true
    end

    it 'uses specified interval when provided' do
      result = described_class.generate('/tmp/video.mp4', output_path: '/tmp/sheet.jpg', interval: 5)
      expect(result[:interval]).to eq(5)
      expect(result[:frame_count]).to eq(24)
    end

    it 'handles windowed generation with start/end times' do
      result = described_class.generate(
        '/tmp/video.mp4',
        output_path: '/tmp/zoom.jpg',
        start_time: 45.0, end_time: 60.0, interval: 2
      )
      expect(result[:interval]).to eq(2)
      expect(result[:frame_count]).to eq(8) # 15s / 2s
      expect(result[:timestamps]).to eq([45.0, 47.0, 49.0, 51.0, 53.0, 55.0, 57.0, 59.0])
    end

    it 'generates correct timestamps from start time' do
      result = described_class.generate('/tmp/video.mp4', output_path: '/tmp/sheet.jpg')
      expect(result[:timestamps].first).to eq(0)
      expect(result[:timestamps][1]).to eq(10)
    end

    it 'falls back to CPU when GPU fails' do
      allow(described_class).to receive(:gpu_available?).and_return(true)
      call_count = 0
      allow(described_class).to receive(:system) do |*_args|
        call_count += 1
        call_count == 1 ? false : true # GPU fails, CPU succeeds
      end

      result = described_class.generate('/tmp/video.mp4', output_path: '/tmp/sheet.jpg')
      expect(result[:success]).to be true
    end
  end
end
