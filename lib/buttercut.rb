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
# Clips are built by lib/buttercut/export.rb — the only caller — from a cut's
# YAML against its library. Each clip hash carries a media_type
# (video | audio | image) so the generators route it onto the single timeline
# track; every clip must declare one (the constructor requires it). video/audio
# trim with start_at + duration; an image just takes an on-timeline duration:
#   clips = [
#     { path: '/abs/interview.mov', start_at: 2.0, duration: 5.0, media_type: 'video' },
#     { path: '/abs/music.mp3',     start_at: 0.0, duration: 8.0, media_type: 'audio' },
#     { path: '/abs/still.jpg',     start_at: 0.0, duration: 5.0, media_type: 'image' }
#   ]
#   generator = ButterCut.new(clips, editor: :fcpx)
#   generator.save('output.fcpxml')
class ButterCut
  SUPPORTED_EDITORS = [:fcpx, :resolve, :premiere].freeze

  def self.new(clips, editor:)
    raise ArgumentError, "editor: parameter is required" if editor.nil?

    unless SUPPORTED_EDITORS.include?(editor)
      raise ArgumentError, "Unsupported editor: #{editor.inspect}. Supported editors: #{SUPPORTED_EDITORS.map(&:inspect).join(', ')}"
    end

    case editor
    when :fcpx
      ButterCut::FCPX.new(clips)
    when :resolve
      ButterCut::Resolve.new(clips)
    when :premiere
      ButterCut::Premiere.new(clips)
    else
      raise ArgumentError, "Editor #{editor.inspect} is not yet implemented."
    end
  end
end
