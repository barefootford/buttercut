# frozen_string_literal: true

# A clip in a library is either a video or a still image. `Media` is the single
# owner of that distinction: the extension → type rule lives here, and every
# place that needs to branch on "is this a still?" asks `Media` rather than
# re-deriving the rule from a path. Callers pass a path (or a clip record's
# `'path'`) to the class predicates below — that's the only API.
#
# Three extension categories, all keyed off the (lowercased) extension:
#   - IMAGE_EXTENSIONS   — stills the editors import directly (jpg, png, …).
#   - CONVERT_EXTENSIONS — stills that must be converted to JPEG first (HEIC/HEIF).
#     ffprobe reads an iPhone HEIC as several tiled sub-streams, so probing it for
#     dimensions returns a tile size, not the photo; and an ffmpeg built without
#     an HEVC decoder can't read it at all. Converting once at ingest (via sips,
#     which uses the OS image stack, not ffmpeg) sidesteps both, and hands the
#     editors a format all of them accept. See Media.convert_to_jpeg.
#   - VIDEO_EXTENSIONS   — the footage containers we accept. An explicit allowlist
#     (rather than "anything that isn't an image") so a stray .txt/.pdf/.DS_Store
#     dropped into a footage folder is rejected at ingest with a clear message
#     instead of being run through ffprobe/transcription as if it were video.
#
# Why compute the type instead of storing a flag on the clip hash: the type is
# derived from the filename, so storing it would be a second source of truth that
# can drift. The hash plumbing stays untyped (one mixed `media:` array); the type
# check is computed at the few boundaries that actually branch.
class Media
  IMAGE_EXTENSIONS   = %w[.jpg .jpeg .png .gif .tif .tiff .webp .bmp].freeze
  CONVERT_EXTENSIONS = %w[.heic .heif].freeze
  VIDEO_EXTENSIONS   = %w[
    .mov .mp4 .m4v .avi .mkv .mts .m2ts .ts .mxf
    .mpg .mpeg .m2v .wmv .flv .webm .3gp .r3d .braw
  ].freeze

  def self.extname(path) = File.extname(path.to_s).downcase

  def self.image?(path)             = IMAGE_EXTENSIONS.include?(extname(path))
  def self.needs_conversion?(path)  = CONVERT_EXTENSIONS.include?(extname(path))
  def self.video?(path)             = VIDEO_EXTENSIONS.include?(extname(path))

  # True for any extension ButterCut knows how to ingest (after conversion, for
  # the convert category). Anything else is an unsupported drop-in.
  def self.supported?(path) = image?(path) || video?(path) || needs_conversion?(path)

  # Convert a HEIC/HEIF still to JPEG using `sips` (macOS-native; uses the OS
  # image stack rather than ffmpeg, so it works even when ffmpeg can't decode
  # HEVC and it composes the full-resolution image rather than a tile). Returns
  # the destination path. Raises if the convert fails.
  def self.convert_to_jpeg(src, dest)
    raise ArgumentError, "source image not found: #{src}" unless File.exist?(src.to_s)

    ok = system('sips', '-s', 'format', 'jpeg', src.to_s, '--out', dest.to_s,
                out: File::NULL, err: File::NULL)
    raise "image conversion failed (sips) for #{src}" unless ok && File.exist?(dest.to_s)

    dest.to_s
  end
end

if __FILE__ == $PROGRAM_NAME
  # Convert a HEIC/HEIF still to JPEG. Used by the create-library /
  # process-library skills after they ask the user where the JPEG should live.
  #   ruby lib/buttercut/media.rb convert <src.heic> <dest.jpg>
  if ARGV[0] == 'convert' && ARGV.length == 3
    puts Media.convert_to_jpeg(ARGV[1], ARGV[2])
  else
    warn 'Usage: ruby lib/buttercut/media.rb convert <src.heic> <dest.jpg>'
    exit 1
  end
end
