require 'spec_helper'

RSpec.describe ButterCut do
  let(:video_file_path) { '/Users/andrew/code/buttercut/media/MVI_0323_720p.mov' }
  let(:clips) { [{ path: video_file_path }] }

  describe '.new factory method' do
    it 'creates a ButterCut::FCPX instance when editor is :fcpx' do
      generator = ButterCut.new(clips, editor: :fcpx)
      expect(generator).to be_a(ButterCut::FCPX)
    end

    it 'creates a ButterCut::FCP7 instance when editor is :fcp7' do
      generator = ButterCut.new(clips, editor: :fcp7)
      expect(generator).to be_a(ButterCut::FCP7)
    end

    it 'requires editor parameter' do
      expect { ButterCut.new(clips) }.to raise_error(ArgumentError, /missing keyword.*editor/)
    end

    it 'raises error for unsupported editor' do
      expect { ButterCut.new(clips, editor: :premiere) }.to raise_error(ArgumentError, /Unsupported editor: :premiere/)
      expect { ButterCut.new(clips, editor: :resolve) }.to raise_error(ArgumentError, /Unsupported editor: :resolve/)
      expect { ButterCut.new(clips, editor: :invalid) }.to raise_error(ArgumentError, /Unsupported editor: :invalid/)
    end
  end
end
