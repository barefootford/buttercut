require 'spec_helper'
require_relative '../../lib/buttercut/editors'

RSpec.describe Editors do
  def on_windows! = allow(Platform).to receive(:host_os).and_return('mingw32')
  def on_mac!     = allow(Platform).to receive(:host_os).and_return('darwin24')

  describe '.available' do
    it 'offers all three on macOS' do
      on_mac!
      expect(Editors.available.map { |choice| choice[:value] }).to eq(%w[fcpx premiere resolve])
    end

    it 'drops Final Cut everywhere else' do
      on_windows!
      expect(Editors.available.map { |choice| choice[:value] }).to eq(%w[premiere resolve])
    end

    it 'answers with just what a caller needs to render a choice' do
      on_mac!
      expect(Editors.available.first.keys).to contain_exactly(:value, :label)
    end
  end

  describe '.default' do
    it 'is Final Cut on macOS' do
      on_mac!
      expect(Editors.default).to eq('fcpx')
    end

    # The one of the two that's free and runs everywhere.
    it 'is Resolve off macOS' do
      on_windows!
      expect(Editors.default).to eq('resolve')
    end
  end

  describe '.unavailable_reason' do
    it 'explains a macOS-only editor picked on another platform' do
      on_windows!
      expect(Editors.unavailable_reason('fcpx')).to match(/Final Cut Pro X only runs on macOS.*premiere or resolve/m)
    end

    it 'is silent for an editor that runs here' do
      on_windows!
      expect(Editors.unavailable_reason('resolve')).to be_nil
      on_mac!
      expect(Editors.unavailable_reason('fcpx')).to be_nil
    end

    # A fallback flag for older Resolve versions, not a separate product —
    # warning about it would be noise on every legacy export.
    it 'is silent for resolve_legacy' do
      on_windows!
      expect(Editors.unavailable_reason('resolve_legacy')).to be_nil
    end
  end
end
