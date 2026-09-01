# frozen_string_literal: true

# Reading emitted FCPXML time values back as numbers. A value read as whole
# sequence frames that comes back a Rational landed BETWEEN frames — exactly
# what Final Cut's importer rejects ("not on an edit frame boundary").
module FrameMath
  def fraction_seconds(value)
    numerator, denominator = value.match(%r{\A(\d+)(?:/(\d+))?s\z}).captures

    Rational(numerator.to_i, (denominator || 1).to_i)
  end

  def sequence_frames(value, fps: 24) = fraction_seconds(value) * fps
end

RSpec.configure { |config| config.include FrameMath }
