require 'spec_helper'
require 'tmpdir'
require 'yaml'
require_relative '../../lib/buttercut/settings'

RSpec.describe Settings do
  def with_settings(contents)
    Dir.mktmpdir('settings-spec-') do |dir|
      path = File.join(dir, 'settings.yaml')
      File.write(path, contents) unless contents.nil?
      yield Settings.load(path: path)
    end
  end

  describe '#parallel_jobs' do
    it 'reads a positive integer' do
      with_settings("parallel_jobs: 4\n") { |s| expect(s.parallel_jobs).to eq(4) }
    end

    it 'defaults to 2 when the key is absent' do
      with_settings("whisper_model: small\n") { |s| expect(s.parallel_jobs).to eq(2) }
    end

    it 'defaults to 2 when the value is blank' do
      with_settings("parallel_jobs:\n") { |s| expect(s.parallel_jobs).to eq(2) }
    end

    it 'defaults to 2 for non-numeric or non-positive values' do
      with_settings("parallel_jobs: lots\n") { |s| expect(s.parallel_jobs).to eq(2) }
      with_settings("parallel_jobs: 0\n") { |s| expect(s.parallel_jobs).to eq(2) }
      with_settings("parallel_jobs: -3\n") { |s| expect(s.parallel_jobs).to eq(2) }
    end

    it 'defaults to 2 when the file is missing entirely' do
      with_settings(nil) { |s| expect(s.parallel_jobs).to eq(2) }
    end
  end

  describe '#whisper_model' do
    it 'reads the configured model straight from settings.yaml' do
      with_settings("whisper_model: turbo\n") { |s| expect(s.whisper_model).to eq('turbo') }
    end

    it 'raises when blank or missing — settings.yaml is the source of truth, no code default' do
      with_settings("whisper_model:\n") { |s| expect { s.whisper_model }.to raise_error(/whisper_model is not set/) }
      with_settings("editor: fcpx\n") { |s| expect { s.whisper_model }.to raise_error(/whisper_model is not set/) }
    end
  end

  describe 'beta features' do
    it 'reads every flag as off when the key is absent' do
      with_settings("whisper_model: small\n") do |s|
        expect(s.beta_feature?('multicam')).to be(false)
        expect(s.beta_features).to eq({})
      end
    end

    it 'reads a flag as on only when explicitly truthy' do
      with_settings("beta_features:\n  multicam: true\n  other: false\n") do |s|
        expect(s.beta_feature?('multicam')).to be(true)
        expect(s.beta_feature?('other')).to be(false)
        expect(s.beta_feature?('unlisted')).to be(false)
      end
    end
  end
end
