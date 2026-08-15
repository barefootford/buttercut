require_relative 'fcp7'

class ButterCut
  # Adobe Premiere Pro FCP7 XML (xmeml version 5). Unlike Final Cut and
  # Resolve, Premiere honors only what the XML declares — it ignores source
  # rotation flags and maps frame sizes 1:1 — so rotation and scale-to-fit
  # are baked into the timeline as a Basic Motion filter.
  class Premiere < FCP7
    private

    # One Basic Motion effect carries both corrections; an upright clip at
    # sequence size gets no filter at all.
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

    # Clockwise-positive; 270 is written as -90 so the turn goes the short way.
    def rotation_degrees(asset)
      rotation = asset[:rotation].to_i
      rotation > 180 ? rotation - 360 : rotation
    end

    # Percent scale that letterboxes the post-rotation display frame into the
    # sequence; nil when the clip already fills it (≈100%).
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
