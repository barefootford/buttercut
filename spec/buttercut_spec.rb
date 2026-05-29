require 'spec_helper'

RSpec.describe ButterCut do
  let(:video_file_path) { File.expand_path('./fixtures/media/MVI_0323_720p.mov', __dir__) }
  let(:clips) { [{ path: video_file_path }] }

  describe '.new factory method' do
    it 'creates a ButterCut::FCPX instance when editor is :fcpx' do
      generator = ButterCut.new(clips, editor: :fcpx)
      expect(generator).to be_a(ButterCut::FCPX)
    end

    it 'creates a ButterCut::Resolve instance when editor is :resolve' do
      generator = ButterCut.new(clips, editor: :resolve)
      expect(generator).to be_a(ButterCut::Resolve)
    end

    it 'creates a ButterCut::Premiere instance when editor is :premiere' do
      generator = ButterCut.new(clips, editor: :premiere)
      expect(generator).to be_a(ButterCut::Premiere)
    end

    it 'requires editor parameter' do
      expect { ButterCut.new(clips) }.to raise_error(ArgumentError, /missing keyword.*editor/)
    end

    it 'raises error for unsupported editor' do
      # :fcp7 is the shared format base, not a public editor symbol.
      expect { ButterCut.new(clips, editor: :fcp7) }.to raise_error(ArgumentError, /Unsupported editor: :fcp7/)
      expect { ButterCut.new(clips, editor: :invalid) }.to raise_error(ArgumentError, /Unsupported editor: :invalid/)
    end
  end
end
