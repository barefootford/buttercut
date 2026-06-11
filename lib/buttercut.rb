require_relative 'buttercut/distribution'
require_relative 'buttercut/fcpx'
require_relative 'buttercut/fcp7'
require_relative 'buttercut/resolve'
require_relative 'buttercut/premiere'

# ButterCut - Video editor XML generator
#
# Factory class that creates editor-specific generators based on the editor parameter.
# Currently supports:
#   - :fcpx - Final Cut Pro X (FCPXML 1.8 format)
#   - :resolve - DaVinci Resolve (plain FCP7 / xmeml v5 interchange format)
#   - :premiere - FCP7 XML with explicit rotation for Adobe Premiere Pro
#
# FCP7 itself is the shared xmeml-v5 format base that Resolve and Premiere subclass;
# it is not a public editor symbol.
#
# Example usage:
#   clips = [
#     { path: '/absolute/path/to/video1.mov', start_at: 2.0, duration: 5.0 },
#     { path: '/absolute/path/to/video2.mov' }
#   ]
#   generator = ButterCut.new(clips, editor: :fcpx)
#   generator.save('output.fcpxml')
class ButterCut
  SUPPORTED_EDITORS = [:fcpx, :resolve, :premiere].freeze

  # `timeline:` is an optional explicit output format ({frame_rate:, width:,
  # height:}, any subset) — written by the cut skill into the cut YAML and
  # passed through Export. Without it the format follows the first video clip.
  def self.new(clips, editor:, timeline: nil)
    raise ArgumentError, "editor: parameter is required" if editor.nil?

    unless SUPPORTED_EDITORS.include?(editor)
      raise ArgumentError, "Unsupported editor: #{editor.inspect}. Supported editors: #{SUPPORTED_EDITORS.map(&:inspect).join(', ')}"
    end

    case editor
    when :fcpx
      ButterCut::FCPX.new(clips, timeline: timeline)
    when :resolve
      ButterCut::Resolve.new(clips, timeline: timeline)
    when :premiere
      ButterCut::Premiere.new(clips, timeline: timeline)
    else
      raise ArgumentError, "Editor #{editor.inspect} is not yet implemented."
    end
  end
end
