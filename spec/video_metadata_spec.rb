require 'spec_helper'

RSpec.describe 'VideoMetadata' do
  let(:video_path) { '/Users/andrew/code/buttercut/media/MVI_0323_720p.mov' }

  describe 'metadata extraction' do
    let(:generator) { ButterCut.new([{ path: video_path }], editor: :fcpx) }

    describe '#extract_metadata' do
      it 'extracts metadata from video file using ffprobe' do
        metadata = generator.extract_metadata(video_path)

        expect(metadata).to be_a(Hash)
        expect(metadata).to have_key('streams')
        expect(metadata).to have_key('format')
      end

      it 'finds video stream' do
        metadata = generator.extract_metadata(video_path)
        video_stream = metadata['streams'].find { |s| s['codec_type'] == 'video' }

        expect(video_stream).not_to be_nil
        expect(video_stream['codec_type']).to eq('video')
      end

      it 'finds audio stream' do
        metadata = generator.extract_metadata(video_path)
        audio_stream = metadata['streams'].find { |s| s['codec_type'] == 'audio' }

        expect(audio_stream).not_to be_nil
        expect(audio_stream['codec_type']).to eq('audio')
      end
    end

    describe '#video_width' do
      it 'extracts video width' do
        width = generator.video_width(video_path)
        expect(width).to eq(1280)
      end
    end

    describe '#video_height' do
      it 'extracts video height' do
        height = generator.video_height(video_path)
        expect(height).to eq(720)
      end
    end

    describe '#video_duration' do
      it 'extracts video duration in seconds' do
        duration = generator.video_duration(video_path)
        expect(duration).to be_within(0.01).of(6.044042)
      end
    end

    describe '#frame_rate' do
      it 'extracts frame rate as a rational string' do
        frame_rate = generator.frame_rate(video_path)
        # Expected: "24000/1001" which is r_frame_rate (23.976 fps)
        expect(frame_rate).to eq("24000/1001")
      end
    end

    describe '#frame_duration' do
      it 'converts frame rate to frame duration' do
        frame_duration = generator.frame_duration(video_path)
        # Frame duration is the reciprocal of frame rate
        # 24000/1001 fps -> 1001/24000s per frame
        expect(frame_duration).to eq("1001/24000s")
      end
    end

    describe '#audio_sample_rate' do
      it 'extracts audio sample rate' do
        sample_rate = generator.audio_sample_rate(video_path)
        expect(sample_rate).to eq("48000")
      end
    end

    describe '#color_space' do
      it 'extracts color space information' do
        color_space = generator.color_space(video_path)
        # Expected format: "1-1-1 (Rec. 709)" based on bt709
        expect(color_space).to include("709")
      end
    end
  end
end
