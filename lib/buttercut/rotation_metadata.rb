# frozen_string_literal: true

# Reads container rotation metadata from an ffprobe video stream and returns the
# degrees clockwise (0/90/180/270) the source must be rotated to display upright.
# Shared by the contact-sheet pipeline and the editor exporters so orientation
# handling stays consistent across the app. Extend it onto a class to expose
# both methods as class methods.
module RotationMetadata
  # Old MP4/MOV containers store rotation in the stream `rotate` tag (clockwise).
  # Modern files store a displaymatrix in `side_data_list[i].rotation` measured
  # counter-clockwise — negate it. Returns degrees clockwise in 0..359, 0 when
  # there's no rotation metadata.
  def extract_rotation(stream)
    tag = stream.dig('tags', 'rotate') || stream.dig('tags', 'ROTATE')
    return normalize_rotation(tag.to_i) if tag

    side = (stream['side_data_list'] || []).find { |sd| sd['rotation'] }
    return normalize_rotation(-side['rotation'].to_i) if side

    0
  end

  def normalize_rotation(degrees)
    ((degrees.to_i % 360) + 360) % 360
  end
end
