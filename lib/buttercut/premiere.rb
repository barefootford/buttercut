require_relative 'fcp7'

class ButterCut
  # Adobe Premiere Pro FCP7 XML (xmeml version 5).
  #
  # Shares the FCP7 base with the Resolve generator but diverges on rotation. Resolve
  # (and Final Cut) read the source file's own rotation flag on import and auto-correct,
  # so vertical footage stored as a rotated landscape frame comes in upright — the plain
  # FCP7 output is enough. Premiere honors ONLY what the XML declares: it ignores the
  # source rotation flag, so the same XML imports sideways. Premiere therefore needs the
  # rotation written explicitly into the timeline.
  #
  # The same gap applies to frame size. Final Cut (spatial conform) and Resolve ("scale
  # entire image to fit") auto-fit a clip whose native resolution differs from the
  # sequence; Premiere maps an FCP7 clip 1:1, so a 4K clip in a 1080 timeline imports
  # cropped to its center (i.e. "zoomed in"). Premiere therefore also needs a scale-to-fit
  # written explicitly — folded into the same Basic Motion filter as the rotation.
  #
  class Premiere < FCP7
    # The sequence frame follows the first video clip's *display* orientation, so a
    # quarter-turn source gives a portrait timeline (the stored landscape dimensions
    # swapped) rather than a landscape one the rotated footage can't fill. Stills
    # carry no rotation flag, so the check keys off the first video clip; an explicit
    # `timeline:` block still wins (format_width/height in the base check it first).
    def source_format_width
      first_video_path && quarter_turn?(first_video_path) ? video_height(first_video_path) : super
    end

    def source_format_height
      first_video_path && quarter_turn?(first_video_path) ? video_width(first_video_path) : super
    end

    private

    def quarter_turn?(video_path)
      [90, 270].include?(video_rotation(video_path))
    end

    # Premiere ignores both the source rotation flag and any frame-size mismatch, so bake
    # the rotation AND a scale-to-fit into the timeline as one Basic Motion effect. A clip
    # already upright and at sequence size needs neither, so it gets no filter at all.
    def add_video_filters(xml, payload)
      degrees = rotation_degrees(payload[:asset])
      scale = scale_to_fit(payload[:asset])
      return if degrees.zero? && scale.nil?

      xml.filter do
        xml.effect do
          xml.name 'Basic Motion'
          xml.effectid 'basic'
          xml.effectcategory 'motion'
          xml.effecttype 'motion'
          xml.mediatype 'video'
          if scale
            xml.parameter do
              xml.parameterid 'scale'
              xml.name 'Scale'
              xml.valuemin 0
              xml.valuemax 1000
              xml.value scale
            end
          end
          unless degrees.zero?
            xml.parameter do
              xml.parameterid 'rotation'
              xml.name 'Rotation'
              xml.valuemin(-100000)
              xml.valuemax 100000
              xml.value degrees
            end
          end
        end
      end
    end

    # Rotation clockwise-positive; 270 is written as -90 so the applied turn is the short
    # way around. 0 (upright) means no rotation parameter.
    def rotation_degrees(asset)
      rotation = asset[:rotation].to_i
      rotation > 180 ? rotation - 360 : rotation
    end

    # Percent scale that fits the clip's *display* frame (post-rotation) inside the
    # sequence, contained (letterboxed) so nothing is cropped — the min of the width and
    # height ratios. Returns nil when the clip already fills the frame (≈100%), so a
    # same-size clip gets no scale parameter. Stills are scaled too: a 4K screenshot in a
    # 1080 timeline would otherwise zoom the same way a 4K video does.
    def scale_to_fit(asset)
      return nil unless asset[:width] && asset[:height]

      quarter = [90, 270].include?(asset[:rotation].to_i)
      display_width = quarter ? asset[:height] : asset[:width]
      display_height = quarter ? asset[:width] : asset[:height]

      factor = [format_width.to_f / display_width, format_height.to_f / display_height].min
      percent = (factor * 100).round(4)
      return nil if (percent - 100).abs < 0.01

      percent
    end
  end
end
