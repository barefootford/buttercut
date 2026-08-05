require 'spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../lib/buttercut/script_extractor'

RSpec.describe ScriptExtractor do
  def with_transcript(segments)
    Dir.mktmpdir('script-extractor-spec-') do |dir|
      path = File.join(dir, 'transcript.json')
      File.write(path, JSON.generate({ 'segments' => segments }))
      yield path
    end
  end

  describe '.extract' do
    it 'writes one line per segment, stripped, to stdout' do
      with_transcript([{ 'text' => '  Hello there.  ' }, { 'text' => 'General Kenobi.' }]) do |path|
        expect { described_class.extract(path) }.to output("Hello there.\nGeneral Kenobi.\n").to_stdout
      end
    end

    it 'drops segments whose text is blank or whitespace-only' do
      with_transcript([{ 'text' => 'Real line.' }, { 'text' => '   ' }, { 'text' => '' }]) do |path|
        expect { described_class.extract(path) }.to output("Real line.\n").to_stdout
      end
    end

    it 'raises when the transcript has no segments key' do
      Dir.mktmpdir('script-extractor-spec-') do |dir|
        path = File.join(dir, 'transcript.json')
        File.write(path, JSON.generate({ 'language' => 'en' }))
        expect { described_class.extract(path) }.to raise_error(/no 'segments' key/)
      end
    end
  end

  describe '.new' do
    it 'raises when transcript_path is nil or empty' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /required/)
      expect { described_class.new('') }.to raise_error(ArgumentError, /required/)
    end

    it 'raises when the transcript file does not exist' do
      expect { described_class.new('/nonexistent/transcript.json') }.to raise_error(ArgumentError, /not found/)
    end
  end
end
