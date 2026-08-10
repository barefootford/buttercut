require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/report'

# The one part that can quietly go wrong on a real install: the gate between
# the user's error_reporting choice and an upload.
RSpec.describe Report do
  def settings(contents)
    Dir.mktmpdir('report-spec-') do |dir|
      path = File.join(dir, 'settings.yaml')
      File.write(path, contents)
      return Settings.load(path: path)
    end
  end

  def bug(contents) = described_class.new(kind: 'bug', action: 'export', error_class: 'RuntimeError',
                                          settings: settings(contents))

  before { allow(Library).to receive(:developer?).and_return(false) }

  describe '#refusal' do
    it 'permits a send once the user has said always or ask' do
      expect(bug("error_reporting: always\n").refusal).to be_nil
      expect(bug("error_reporting: ask\n").refusal).to be_nil
    end

    it 'refuses on never, and treats missing or unrecognized values as not yet asked' do
      expect(bug("error_reporting: never\n").refusal).to match(/chose never/)
      expect(bug("whisper_model: small\n").refusal).to match(/hasn't asked/)
      expect(bug("error_reporting: yes please\n").refusal).to match(/hasn't asked/)
    end

    it 'refuses on a developer checkout even with consent on file' do
      allow(Library).to receive(:developer?).and_return(true)

      expect(bug("error_reporting: always\n").refusal).to match(/developer checkout/)
    end

    it 'never gates a feature request on the error-reporting choice' do
      feature = described_class.new(kind: 'feature', title: 'Multicam', settings: settings("error_reporting: never\n"))

      expect(feature.refusal).to be_nil
    end
  end

  describe '#fingerprint' do
    it 'ignores the message, so one bug seen on two files stays one bug' do
      seen = ['a.mov', 'b.mov'].map do |file|
        described_class.new(kind: 'bug', action: 'export', error_class: 'RuntimeError',
                            message: "no such file: #{file}", frame: 'lib/buttercut/export_core.rb:88').fingerprint
      end

      expect(seen.uniq.size).to eq(1)
      expect(seen.first).to match(/\A\h{12}\z/)
    end
  end
end
