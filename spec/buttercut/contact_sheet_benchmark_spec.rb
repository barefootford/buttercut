require 'spec_helper'
require 'benchmark'
require 'tmpdir'
require_relative '../../lib/buttercut/contact_sheet'

# Wall-time regression checks. Opt-in: `rspec --tag benchmark`. Each clip is run 3x
# and the best wall time is compared against the inlined baseline. Tolerance is generous
# (2x) because wall times are decode-bound and noisy; the regressions we care about
# (single-pass on heavy long-GOP) are 5-100x.
RSpec.describe ContactSheet, 'wall-time regression', :benchmark do
  tolerance = 2.0
  runs_per_case = 3

  fixtures = [
    { file: 'h264_yuv420p.mp4',         baseline: 0.819, description: 'H.264 8-bit 4:2:0 — typical consumer footage, hwaccel applies' },
    { file: 'hevc_yuv420p10le.mov',     baseline: 1.035, description: 'HEVC 10-bit 4:2:0 — drone/iPhone, hwaccel handles 10-bit' },
    { file: 'h264_yuv422p10le_2s.mp4',  baseline: 2.089, description: 'H.264 10-bit 4:2:2, 2s — heavy short clip, dispatched to single-pass' },
    { file: 'h264_yuv422p10le_35s.mp4', baseline: 14.17, description: 'H.264 10-bit 4:2:2, 35s — heavy long clip, dispatched to seek-and-grab' },
    { file: 'hevc_yuv422p10le.mov',     baseline: 0.706, description: 'HEVC 10-bit 4:2:2 — chroma forces software decode' },
    { file: 'hevc_portrait_native.mov', baseline: 0.39,  description: 'HEVC portrait, native vertical dimensions — no rotation tag' },
    { file: 'prores.mov',               baseline: 0.725, description: 'ProRes — all-intra, every frame is a keyframe' },
    { file: 'mjpeg.mov',                baseline: 0.19,  description: 'MJPEG — all-intra, smallest cost' }
  ].freeze

  around do |example|
    Dir.mktmpdir('contact-sheet-bench-') do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  define_method(:measure) do |video_path, output_path|
    runs = Array.new(runs_per_case) do
      File.delete(output_path) if File.exist?(output_path)
      silence_stdout { Benchmark.realtime { ContactSheet.extract(video_path, output_path: output_path) } }
    end
    runs.min
  end

  fixtures.each do |fixture|
    it fixture[:description] do |example|
      output = File.join(@tmp_dir, "#{File.basename(fixture[:file], '.*')}.jpg")
      elapsed = measure(Fixtures.path(fixture[:file]), output)
      example.metadata[:description] =
        format('%s (%.1fs, baseline %.1fs)', fixture[:description], elapsed, fixture[:baseline])

      ratio = elapsed / fixture[:baseline]
      expect(ratio).to be <= tolerance,
        format('regression: ratio %.2fx exceeds tolerance %.1fx', ratio, tolerance)
    end
  end
end
