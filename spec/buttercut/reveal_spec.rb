require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/reveal'

RSpec.describe Reveal do
  around do |example|
    Dir.mktmpdir('bc-reveal') do |dir|
      @path = File.join(dir, 'cut.fcpxml')
      File.write(@path, '<xml/>')
      example.run
    end
  end

  def stub_open(succeeding: [])
    allow(Reveal).to receive(:system) { |*argv| succeeding.include?(argv[2]) }
  end

  it 'opens with the named application when the platform can' do
    allow(Platform).to receive(:open_with_app_argv) { |app, path| ['open', '-a', app, path] }
    stub_open(succeeding: ['Final Cut Pro'])

    expect(Reveal.perform(@path, 'Final Cut Pro')).to eq("opened in Final Cut Pro: #{@path}")
  end

  # `open -a` wants the exact installed name, and editors ship version-suffixed
  # ones — the retry is what keeps "it isn't installed" from being a lie.
  it 'retries with the installed name when the exact one misses' do
    allow(Platform).to receive(:open_with_app_argv) { |app, path| ['open', '-a', app, path] }
    allow(Reveal).to receive(:installed_app_matching).with('Adobe Premiere Pro')
                                                     .and_return('Adobe Premiere Pro 2026')
    stub_open(succeeding: ['Adobe Premiere Pro 2026'])

    expect(Reveal.perform(@path, 'Adobe Premiere Pro'))
      .to eq("opened in Adobe Premiere Pro 2026: #{@path}")
  end

  it 'falls back to revealing when no application can open it' do
    allow(Platform).to receive(:open_with_app_argv).and_return(nil)
    allow(Platform).to receive(:reveal_argv).and_return(['explorer.exe', "/select,#{@path}"])
    allow(Reveal).to receive(:system).and_return(false) # Explorer lies about its status

    expect(Reveal.perform(@path, 'Adobe Premiere Pro'))
      .to eq("revealed in the file manager: #{@path}")
  end

  it 'just reports the path where there is nothing to open or reveal with' do
    allow(Platform).to receive(:open_with_app_argv).and_return(nil)
    allow(Platform).to receive(:reveal_argv).and_return(nil)

    expect(Reveal.perform(@path)).to eq("exported to: #{@path}")
  end

  it 'raises on a path that is not there' do
    expect { Reveal.perform(File.join(File.dirname(@path), 'missing.xml')) }
      .to raise_error(ArgumentError, /No such file/)
  end

  describe '.installed_app_names' do
    it 'finds bundles nested one folder deep, the way Adobe installs them' do
      Dir.mktmpdir('bc-apps') do |apps|
        Dir.mkdir(File.join(apps, 'Adobe Premiere Pro 2026'))
        File.write(File.join(apps, 'Adobe Premiere Pro 2026', 'Adobe Premiere Pro 2026.app'), '')
        File.write(File.join(apps, 'Final Cut Pro.app'), '')
        File.write(File.join(apps, 'notes.txt'), '')
        stub_const('Reveal::APPLICATION_DIRS', [apps, '/definitely/not/here'])

        expect(Reveal.installed_app_names)
          .to contain_exactly('Adobe Premiere Pro 2026', 'Final Cut Pro')
        expect(Reveal.installed_app_matching('Adobe Premiere Pro')).to eq('Adobe Premiere Pro 2026')
      end
    end
  end
end
