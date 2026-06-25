require 'spec_helper'

# The edition shims (editor_base.rb, export.rb, fcpx.rb, fcp7.rb) pick their
# implementation through these helpers. Pin the contract here.
RSpec.describe ButterCut do
  describe 'edition predicates' do
    it 'pro? and core? reflect EDITION and are mutually exclusive' do
      expect(ButterCut.pro?).to eq(ButterCut::EDITION == :pro)
      expect(ButterCut.core?).to eq(ButterCut::EDITION == :core)
      expect(ButterCut.pro?).not_to eq(ButterCut.core?)
    end
  end

  describe '.engine_variant' do
    it 'falls back to the _core variant when no _pro file is present' do
      allow(File).to receive(:exist?).and_return(false)
      expect(ButterCut.engine_variant('fcpx')).to eq('fcpx_core')
    end

    it 'prefers the _pro variant in Pro when that file exists' do
      allow(ButterCut).to receive(:pro?).and_return(true)
      allow(File).to receive(:exist?).and_return(true)
      expect(ButterCut.engine_variant('fcpx')).to eq('fcpx_pro')
    end

    it 'uses the _core variant in core even if a _pro file exists' do
      allow(ButterCut).to receive(:pro?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      expect(ButterCut.engine_variant('fcpx')).to eq('fcpx_core')
    end
  end
end
