# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/buttercut/format_checker'

# Grouping/report logic runs against an injected prober (a lambda returning
# canned ffprobe stream JSON per path), so no real media or ffprobe is needed.
# One example at the bottom runs the real prober over the committed fixture
# clips to pin the ffprobe integration.
RSpec.describe FormatChecker do
  around do |example|
    Dir.mktmpdir('format-checker-') do |dir|
      @dir = dir
      example.run
    end
  end

  # Create an empty stand-in file (the checker only needs it to exist — the
  # injected prober supplies the metadata) and return its path.
  def touch(filename)
    path = File.join(@dir, filename)
    FileUtils.touch(path)
    path
  end

  def probe_data(width:, height:, fps: '30000/1001', rotation: nil, audio: 48_000)
    video = { 'codec_type' => 'video', 'width' => width, 'height' => height, 'r_frame_rate' => fps }
    video['side_data_list'] = [{ 'rotation' => rotation }] if rotation
    streams = [video]
    streams << { 'codec_type' => 'audio', 'sample_rate' => audio.to_s } if audio
    { 'streams' => streams }
  end

  # Build a checker over `specs` = { 'filename.mov' => probe_data(...) }.
  def checker_for(specs)
    paths = specs.keys.map { |filename| touch(filename) }
    described_class.new(paths, prober: ->(path) { specs.fetch(File.basename(path)) })
  end

  describe 'uniform footage' do
    it 'reports one format and no summary' do
      checker = checker_for(
        'a.mov' => probe_data(width: 1920, height: 1080),
        'b.mov' => probe_data(width: 1920, height: 1080)
      )

      expect(checker.uniform?).to be(true)
      expect(checker.formats.size).to eq(1)
      expect(checker.outliers).to be_empty
      expect(checker.mixed_summary).to be_nil

      report = checker.report
      expect(report['uniform']).to be(true)
      expect(report['dominant_format']).to include('resolution' => '1920x1080', 'fps' => '29.97', 'count' => 2)
      expect(report['outlier_clips']).to eq([])
      expect(report['unreadable']).to eq([])
    end

    it 'is uniform when there are no clips at all' do
      checker = described_class.new([])

      expect(checker.uniform?).to be(true)
      expect(checker.report).to include('formats' => [], 'dominant_format' => nil, 'uniform' => true)
    end
  end

  describe 'mixed footage' do
    let(:checker) do
      checker_for(
        'small.mp4' => probe_data(width: 1280, height: 720, fps: '25/1'),
        'a.mov' => probe_data(width: 3840, height: 2160),
        'b.mov' => probe_data(width: 3840, height: 2160)
      )
    end

    it 'groups formats biggest first and lists the outliers' do
      expect(checker.uniform?).to be(false)
      expect(checker.formats.map { |f| f['resolution'] }).to eq(%w[3840x2160 1280x720])
      expect(checker.dominant).to include('count' => 2, 'clips' => %w[a.mov b.mov])
      expect(checker.outliers).to eq(['small.mp4'])
    end

    it 'writes an editor-friendly summary naming every clip' do
      expect(checker.mixed_summary(subject: 'This cut')).to eq(
        'This cut mixes 2 formats: 3840x2160 @ 29.97fps (2 clips: a.mov, b.mov); ' \
        '1280x720 @ 25fps (1 clip: small.mp4).'
      )
    end

    it 'keeps input order among equally-sized groups' do
      checker = checker_for(
        'first.mov' => probe_data(width: 1920, height: 1080),
        'second.mov' => probe_data(width: 1280, height: 720)
      )

      expect(checker.formats.map { |f| f['resolution'] }).to eq(%w[1920x1080 1280x720])
    end
  end

  describe 'probed values' do
    it 'labels whole and NTSC rates naturally' do
      checker = checker_for(
        'pal.mov' => probe_data(width: 1920, height: 1080, fps: '25/1'),
        'ntsc.mov' => probe_data(width: 1920, height: 1080, fps: '24000/1001')
      )

      expect(checker.clips.map { |c| c['fps'] }).to eq(%w[25 23.98])
      expect(checker.clips.first['frame_rate']).to eq('25/1')
    end

    it 'uses display dimensions for rotated clips' do
      checker = checker_for(
        'portrait.mov' => probe_data(width: 1920, height: 1080, rotation: -90),
        'upright.mov' => probe_data(width: 1080, height: 1920)
      )

      expect(checker.clips.map { |c| c['resolution'] }.uniq).to eq(['1080x1920'])
      expect(checker.uniform?).to be(true)
    end

    it 'tracks audio sample rates without letting them split formats' do
      checker = checker_for(
        'a.mov' => probe_data(width: 1920, height: 1080, audio: 48_000),
        'b.mov' => probe_data(width: 1920, height: 1080, audio: 44_100),
        'silent.mov' => probe_data(width: 1920, height: 1080, audio: nil)
      )

      expect(checker.uniform?).to be(true)
      expect(checker.mixed_audio?).to be(true)
      expect(checker.report['mixed_audio_sample_rates']).to eq([48_000, 44_100])
    end
  end

  describe 'unreadable clips' do
    it 'reports a missing file as an error row and keeps judging the rest' do
      readable = touch('a.mov')
      checker = described_class.new(
        [readable, File.join(@dir, 'gone.mov')],
        prober: ->(_path) { probe_data(width: 1920, height: 1080) }
      )

      expect(checker.unreadable).to contain_exactly(hash_including('filename' => 'gone.mov', 'error' => 'file not found'))
      expect(checker.uniform?).to be(true)
      expect(checker.report['formats'].first['count']).to eq(1)
    end

    it 'captures prober failures per clip instead of raising' do
      path = touch('boom.mov')
      checker = described_class.new([path], prober: ->(_p) { raise 'ffprobe failed: exploded' })

      expect(checker.unreadable.first['error']).to eq('ffprobe failed: exploded')
      expect(checker.formats).to be_empty
    end

    it 'rejects streams with broken dimensions or frame rates' do
      checker = checker_for(
        'nodims.mov' => probe_data(width: 0, height: 1080),
        'norate.mov' => probe_data(width: 1920, height: 1080, fps: '0/0'),
        'novideo.mov' => { 'streams' => [{ 'codec_type' => 'audio', 'sample_rate' => '48000' }] }
      )

      expect(checker.unreadable.map { |c| c['error'] }).to eq(
        ['unreadable dimensions', 'unreadable frame rate: "0/0"', 'no video stream']
      )
    end
  end

  describe 'real ffprobe integration' do
    it 'reads the committed fixture clips as one uniform 720p format' do
      checker = described_class.new([fixture_media('MVI_0309_720p.mov'), fixture_media('MVI_0323_720p.mov')])

      expect(checker.uniform?).to be(true)
      expect(checker.dominant).to include('resolution' => '1280x720', 'fps' => '23.98', 'count' => 2)
      expect(checker.audio_sample_rates).to eq([48_000])
    end
  end
end
