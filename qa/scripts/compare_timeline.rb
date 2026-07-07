# frozen_string_literal: true

# Compares an editor's actual imported timeline against the fixture's
# expected_<scenario>.json. Both sides use the same normalized shape; each
# editor's verify_* runner is responsible for producing the actual half:
#
#   {
#     "timeline" => { "frame_rate" => 30, "width" => 1280, "height" => 720, "total_frames" => 690 },
#     "clips"    => [ { "source" => "qa_clipB.mov", "type" => "video",
#                       "record_in" => 0, "record_out" => 180,
#                       "source_in" => 300, "source_out" => 480,   # video only
#                       "mute" => false },                          # only when observable
#                     ... ]
#   }
#
# Frame comparisons are exact — the fixture is built frame-aligned on purpose.
# A key missing from an actual clip is reported as skipped, not failed: not
# every editor exposes every fact (e.g. Resolve's API doesn't expose mute).
#
# CLI: ruby qa/scripts/compare_timeline.rb <expected.json> <actual.json>

require 'json'

module QaCompare
  TIMELINE_KEYS = %w[frame_rate width height total_frames].freeze
  CLIP_KEYS = %w[source type record_in record_out source_in source_out mute].freeze

  module_function

  def compare(expected, actual)
    failures = []
    skipped = []
    checked = 0
    check = lambda do |label, want, got|
      checked += 1
      failures << "#{label}: expected #{want.inspect}, got #{got.inspect}" unless values_match?(want, got)
    end

    TIMELINE_KEYS.each do |key|
      got = actual.dig('timeline', key)
      next skipped << "timeline.#{key}" if got.nil?

      check.call("timeline.#{key}", expected.dig('timeline', key), got)
    end

    want_clips = expected.fetch('clips')
    got_clips  = actual.fetch('clips', [])
    check.call('clip count', want_clips.length, got_clips.length)

    want_clips.zip(got_clips).each_with_index do |(want, got), i|
      label = "clip #{i + 1} (#{want['source']})"
      next failures << "#{label}: missing from imported timeline" if got.nil?

      CLIP_KEYS.each do |key|
        next unless want.key?(key)
        next skipped << "#{label}.#{key}" unless got.key?(key)

        check.call("#{label}.#{key}", want[key], got[key])
      end
    end

    { 'pass' => failures.empty?, 'checked' => checked, 'failures' => failures, 'skipped' => skipped.sort }
  end

  # Editors return numbers as strings ("30", "720") or floats (30.0); compare
  # numerically when both sides look numeric, exactly otherwise.
  def values_match?(want, got)
    if numeric?(want) && numeric?(got)
      Float(want) == Float(got)
    else
      want.to_s == got.to_s
    end
  end

  def numeric?(value)
    value.is_a?(Numeric) || (value.is_a?(String) && Float(value, exception: false))
  end

  def report(result, label:)
    status = result['pass'] ? 'PASS' : 'FAIL'
    lines = ["#{status}: #{label} — #{result['checked']} checks, #{result['failures'].length} failures"]
    result['failures'].each { |f| lines << "  ✗ #{f}" }
    lines << "  (not observable in this editor: #{result['skipped'].join(', ')})" unless result['skipped'].empty?
    lines.join("\n")
  end
end

if $PROGRAM_NAME == __FILE__
  expected_path, actual_path = ARGV
  abort 'Usage: ruby qa/scripts/compare_timeline.rb <expected.json> <actual.json>' unless expected_path && actual_path

  result = QaCompare.compare(JSON.parse(File.read(expected_path)), JSON.parse(File.read(actual_path)))
  puts QaCompare.report(result, label: "#{File.basename(actual_path)} vs #{File.basename(expected_path)}")
  exit(result['pass'] ? 0 : 1)
end
