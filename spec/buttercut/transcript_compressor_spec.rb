require 'spec_helper'

RSpec.describe Buttercut::TranscriptCompressor do
  let(:sample_json) do
    {
      'video_path' => '/path/to/video.mov',
      'language' => 'en',
      'segments' => [
        {
          'start' => 2.917,
          'end' => 7.586,
          'text' => 'Hey, good afternoon everybody.',
          'words' => [
            { 'word' => 'Hey,', 'start' => 2.917, 'end' => 3.012 },
            { 'word' => 'good', 'start' => 3.012, 'end' => 3.156 },
            { 'word' => 'afternoon', 'start' => 3.156, 'end' => 3.678 },
            { 'word' => 'everybody.', 'start' => 3.678, 'end' => 4.123 }
          ]
        },
        {
          'start' => 7.586,
          'end' => 12.345,
          'text' => 'Today I want to talk about video editing.',
          'words' => [
            { 'word' => 'Today', 'start' => 7.586, 'end' => 7.851 },
            { 'word' => 'I', 'start' => 7.851, 'end' => 7.912 }
          ]
        }
      ]
    }
  end

  let(:visual_json) do
    {
      'video_path' => '/path/to/video.mov',
      'language' => 'en',
      'segments' => [
        {
          'start' => 2.917,
          'end' => 7.586,
          'text' => 'Hey, good afternoon everybody.',
          'visual' => 'Man in red shirt speaking to camera in medium shot. Home office with bookshelf.'
        },
        {
          'start' => 35.474,
          'end' => 56.162,
          'text' => '',
          'visual' => 'Green bicycle parked in front of building. Urban street with trees.',
          'b_roll' => true
        }
      ]
    }
  end

  describe '.compress' do
    context 'with audio transcript (word-level timing)' do
      it 'compresses to pipe-delimited format' do
        result = described_class.compress(sample_json, include_words: true)

        expect(result).to include('@/path/to/video.mov|en')
        expect(result).to include('# 2.92-7.59 | Hey, good afternoon everybody.')
        expect(result).to include('w: Hey,|2.92-3.01 good|3.01-3.16 afternoon|3.16-3.68 everybody.|3.68-4.12')
        expect(result).to include('# 7.59-12.34 | Today I want to talk about video editing.')
      end

      it 'formats timestamps to 2 decimal places' do
        result = described_class.compress(sample_json, include_words: true)

        expect(result).to include('2.92')
        expect(result).not_to include('2.917')
      end
    end

    context 'with visual transcript (no word timing)' do
      it 'includes visual descriptions' do
        result = described_class.compress(visual_json, include_words: false)

        expect(result).to include('v: Man in red shirt speaking to camera')
      end

      it 'marks b-roll segments' do
        result = described_class.compress(visual_json, include_words: false)

        expect(result).to include('b: 35.47-56.16 |')
        expect(result).to include('Green bicycle parked')
      end
    end
  end

  describe '.decompress' do
    let(:compressed_audio) do
      <<~TRANSCRIPT
        @/path/to/video.mov|en

        # 2.92-7.59 | Hey, good afternoon everybody.
        w: Hey,|2.92-3.01 good|3.01-3.16 afternoon|3.16-3.68 everybody.|3.68-4.12

        # 7.59-12.35 | Today I want to talk about video editing.
        w: Today|7.59-7.85 I|7.85-7.91

      TRANSCRIPT
    end

    let(:compressed_visual) do
      <<~TRANSCRIPT
        @/path/to/video.mov|en

        # 2.92-7.59 | Hey, good afternoon everybody.
        v: Man in red shirt speaking to camera in medium shot. Home office with bookshelf.

        b: 35.47-56.16 |
          Green bicycle parked in front of building. Urban street with trees.

      TRANSCRIPT
    end

    it 'decompresses audio transcript correctly' do
      result = described_class.decompress(compressed_audio)

      expect(result['video_path']).to eq('/path/to/video.mov')
      expect(result['language']).to eq('en')
      expect(result['segments'].length).to eq(2)

      first_segment = result['segments'][0]
      expect(first_segment['start']).to eq(2.92)
      expect(first_segment['end']).to eq(7.59)
      expect(first_segment['text']).to eq('Hey, good afternoon everybody.')
      expect(first_segment['words'].length).to eq(4)
      expect(first_segment['words'][0]['word']).to eq('Hey,')
      expect(first_segment['words'][0]['start']).to eq(2.92)
    end

    it 'decompresses visual transcript correctly' do
      result = described_class.decompress(compressed_visual)

      first_segment = result['segments'][0]
      expect(first_segment['visual']).to include('Man in red shirt')

      second_segment = result['segments'][1]
      expect(second_segment['b_roll']).to be true
      expect(second_segment['visual']).to include('Green bicycle')
    end

    it 'round-trips correctly' do
      compressed = described_class.compress(sample_json, include_words: true)
      decompressed = described_class.decompress(compressed)

      expect(decompressed['video_path']).to eq(sample_json['video_path'])
      expect(decompressed['segments'].length).to eq(sample_json['segments'].length)
    end
  end

  describe 'token reduction' do
    it 'significantly reduces file size' do
      require 'json'

      json_size = JSON.pretty_generate(sample_json).bytesize
      compressed_size = described_class.compress(sample_json, include_words: true).bytesize

      reduction_percent = ((json_size - compressed_size).to_f / json_size * 100).round

      expect(reduction_percent).to be >= 50
      puts "\nToken reduction: #{reduction_percent}% (#{json_size} bytes -> #{compressed_size} bytes)"
    end
  end
end
