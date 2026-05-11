#!/usr/bin/env ruby
# Convert a parakeet-mlx JSON transcript into the WhisperX-shaped JSON the rest
# of ButterCut consumes (segments[], segments[].words[], word_segments[],
# language, video_path). Overwrites the input file in place.

require 'json'

class ParakeetNormalizer
  def self.normalize(transcript_path, video_path, language_code)
    new(transcript_path, video_path, language_code).normalize
  end

  def initialize(transcript_path, video_path, language_code)
    raise ArgumentError, "transcript_path is required" if transcript_path.nil? || transcript_path.empty?
    raise ArgumentError, "video_path is required" if video_path.nil? || video_path.empty?
    raise ArgumentError, "language_code is required" if language_code.nil? || language_code.empty?
    @transcript_path = transcript_path
    @video_path = video_path
    @language_code = language_code
  end

  def normalize
    parakeet = load_parakeet
    whisperx = build_whisperx(parakeet)
    write_output(whisperx)
    report(whisperx)
  end

  private

  attr_reader :transcript_path, :video_path, :language_code

  def load_parakeet
    JSON.parse(File.read(transcript_path))
  end

  def build_whisperx(parakeet)
    segments = (parakeet['sentences'] || []).map { |s| build_segment(s) }
    {
      'language' => language_code,
      'video_path' => video_path,
      'segments' => segments,
      'word_segments' => segments.flat_map { |s| s['words'] }
    }
  end

  def build_segment(sentence)
    {
      'start' => sentence['start'],
      'end' => sentence['end'],
      'text' => sentence['text'].to_s.strip,
      'words' => (sentence['tokens'] || []).map { |t| build_word(t) }
    }
  end

  def build_word(token)
    {
      'word' => token['text'].to_s,
      'start' => token['start'],
      'end' => token['end']
    }
  end

  def write_output(data)
    File.write(transcript_path, JSON.pretty_generate(data))
  end

  def report(data)
    puts "Normalized: #{transcript_path} (#{data['segments'].size} segments, #{data['word_segments'].size} words)"
  end
end

if __FILE__ == $PROGRAM_NAME
  transcript_path, video_path, language_code = ARGV
  unless transcript_path && video_path && language_code
    abort "usage: parakeet_normalizer.rb <transcript.json> <video_path> <language_code>"
  end
  abort "file not found: #{transcript_path}" unless File.file?(transcript_path)
  ParakeetNormalizer.normalize(transcript_path, video_path, language_code)
end
