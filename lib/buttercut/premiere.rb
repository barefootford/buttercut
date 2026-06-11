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

    # Premiere ignores the source rotation flag, so bake the rotation into the timeline
    # as a Basic Motion effect. Rotation is clockwise-positive; 270 is written as -90 so
    # the applied turn is the short way around.
    def add_video_filters(xml, payload)
      rotation = payload[:asset][:rotation].to_i
      return if rotation.zero?

      degrees = rotation > 180 ? rotation - 360 : rotation

      xml.filter do
        xml.effect do
          xml.name 'Basic Motion'
          xml.effectid 'basic'
          xml.effectcategory 'motion'
          xml.effecttype 'motion'
          xml.mediatype 'video'
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
end
