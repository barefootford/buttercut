require_relative 'buttercut/fcpx'
require_relative 'buttercut/fcp7'

# ButterCut - Video editor XML generator
#
# Factory class that creates editor-specific generators based on the editor parameter.
# Currently supports:
#   - :fcpx - Final Cut Pro X (FCPXML 1.8 format)
#   - :fcp7 - Final Cut Pro 7 XML (xmeml version 5)
#
# Example usage:
#   clips = [
#     { path: '/absolute/path/to/video1.mov', start_at: 2.0, duration: 5.0 },
#     { path: '/absolute/path/to/video2.mov' }
#   ]
#   generator = ButterCut.new(clips, editor: :fcpx)
#   generator.save('output.fcpxml')
#
# Options:
#   - sequence_frame_rate: Override the sequence frame rate (e.g., 50 for 50fps)
class ButterCut
  SUPPORTED_EDITORS = [:fcpx, :fcp7].freeze

  def self.new(clips, editor:, **options)
    raise ArgumentError, "editor: parameter is required" if editor.nil?

    unless SUPPORTED_EDITORS.include?(editor)
      raise ArgumentError, "Unsupported editor: #{editor.inspect}. Supported editors: #{SUPPORTED_EDITORS.map(&:inspect).join(', ')}"
    end

    case editor
    when :fcpx
      ButterCut::FCPX.new(clips, options)
    when :fcp7
      ButterCut::FCP7.new(clips, options)
    else
      raise ArgumentError, "Editor #{editor.inspect} is not yet implemented."
    end
  end
end
