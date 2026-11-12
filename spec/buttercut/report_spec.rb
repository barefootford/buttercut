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

  describe '#payload' do
    it 'carries the machine facts under platform' do
      allow(Platform).to receive(:facts).and_return('os' => 'windows', 'release' => '10.0.26100',
                                                   'arch' => 'x86_64', 'ruby' => '3.3.11')

      payload = bug("error_reporting: always\n").payload

      expect(payload['schema_version']).to eq(3)
      expect(payload['platform']).to eq('os' => 'windows', 'release' => '10.0.26100', 'arch' => 'x86_64',
                                        'ruby' => '3.3.11')
    end

    it 'still builds when the machine facts are unavailable' do
      allow(Platform).to receive(:facts).and_raise(Errno::ENOENT)

      payload = bug("error_reporting: always\n").payload

      expect(payload['platform']).to be_nil
      expect(payload['buttercut']).to include('version' => ButterCut::VERSION)
    end

    it "names the build with the install's commit" do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--short', 'HEAD', chdir: Library::REPO_ROOT)
                                        .and_return(["578c44a\n", '', status])

      expect(bug("error_reporting: always\n").payload['buttercut'])
        .to eq('version' => ButterCut::VERSION, 'build' => '578c44a', 'edition' => ButterCut::EDITION.to_s)
    end

    it 'sends no build when git cannot say' do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      expect(bug("error_reporting: always\n").payload['buttercut']).to include('build' => nil)
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
