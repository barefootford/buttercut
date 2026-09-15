# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../../lib/buttercut/utf8'

# A shell that never sourced its profile has no LANG/LC_*, so Ruby's locale is
# US-ASCII and non-ASCII clip names arrive on ARGV as invalid strings. These
# specs run real subprocesses under that locale — the condition ButterCut
# reports 18 and 20 came from — instead of faking Encoding.default_external.
RSpec.describe ButterCut::UTF8 do
  ASCII_LOCALE = { 'LC_ALL' => 'C', 'LANG' => nil, 'LC_CTYPE' => nil }.freeze
  REPO = File.expand_path('../..', __dir__)

  def run_ruby(*args)
    Open3.capture3(ASCII_LOCALE, RbConfig.ruby, *args, chdir: REPO)
  end

  describe 'entry points' do
    it 'make the process UTF-8 and retag ARGV, so a clip name survives YAML round-trip' do
      # A script-level require, as every entry point does it; Ruby re-applies
      # the locale after `-r` preloads, so those would not show the fix.
      script = 'require "./lib/buttercut/version"; require "yaml"; ' \
               'print Encoding.default_external, "\n", ARGV[0].to_yaml'
      out, err, status = run_ruby('-e', script, 'clip—one.mp4')

      expect(status).to be_success, err
      expect(out.lines.first.chomp).to eq('UTF-8')
      expect(out).not_to include('!binary')
      expect(out.force_encoding('UTF-8')).to include('clip—one.mp4')
    end

    it 'prepare_audio_script writes a non-ASCII video path as UTF-8 without warnings' do
      Dir.mktmpdir do |dir|
        json = File.join(dir, 'clip.json')
        File.write(json, '{"segments":[{"text":"café","words":[{"word":"café","score":0.9}]}]}')
        video = "/footage/café—take 1.mp4"

        out, err, status = run_ruby('lib/buttercut/prepare_audio_script.rb', json, video)

        expect(status).to be_success, out + err
        expect(err).to eq('')
        expect(out).not_to include('warning')
        data = JSON.parse(File.read(json, encoding: 'UTF-8'))
        expect(data['video_path']).to eq(video)
        expect(data['segments'].first['words'].first).to eq('word' => 'café')
      end
    end
  end

  describe '.heal_media_paths!' do
    it 'retags media paths that loaded as binary back to UTF-8' do
      binary = 'clip—one.mp4'.b
      library = { 'media' => [{ 'path' => binary }, { 'path' => 'plain.mp4' }] }

      described_class.heal_media_paths!(library)

      expect(library['media'][0]['path'].encoding).to eq(Encoding::UTF_8)
      expect(library['media'][0]['path']).to eq('clip—one.mp4')
      expect(library['media'][1]['path']).to eq('plain.mp4')
    end

    it 'tolerates libraries without media' do
      expect { described_class.heal_media_paths!({}) }.not_to raise_error
      expect { described_class.heal_media_paths!({ 'media' => nil }) }.not_to raise_error
    end
  end
end
