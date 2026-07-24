require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/desktop'

RSpec.describe Desktop do
  around do |example|
    Dir.mktmpdir('bc-desktop') do |root|
      @desktop = File.join(root, 'Desktop')
      Dir.mkdir(@desktop)
      @export = File.join(root, 'my cut.fcpxml')
      File.write(@export, '<xml/>')
      example.run
    end
  end

  it 'copies the export to whatever Platform reports as the Desktop' do
    allow(Platform).to receive(:desktop_dir).and_return(@desktop)

    destination = Desktop.copy(@export)

    expect(destination).to eq(File.join(@desktop, 'my cut.fcpxml'))
    expect(File.read(destination)).to eq('<xml/>')
  end

  it 'raises on a source that is not there' do
    allow(Platform).to receive(:desktop_dir).and_return(@desktop)

    expect { Desktop.copy(File.join(File.dirname(@export), 'nope.xml')) }
      .to raise_error(ArgumentError, /No such file/)
  end

  # Inventing the folder would put the file somewhere the user never looks —
  # the exact failure this whole path exists to avoid.
  it 'refuses to invent a Desktop that is not there' do
    missing = File.join(@desktop, 'gone')
    allow(Platform).to receive(:desktop_dir).and_return(missing)

    expect { Desktop.copy(@export) }.to raise_error(ArgumentError, /Desktop folder not found/)
    expect(Dir.exist?(missing)).to be(false)
  end
end
