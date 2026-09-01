require_relative 'editor_base'
require 'nokogiri'

class ButterCut
  # Final Cut Pro X (FCPXML 1.12) implementation. 1.12 keeps the export
  # readable by DaVinci Resolve 19.1.1+ as well as Final Cut.
  class FCPX < EditorBase
    FORMAT_ID = "r1".freeze
    # Resolve's FCPXML importer only parses bare '-96', silently drops '-96dB'
    # Final Cut docs say we should include dB in string, but parses fine without
    MUTE_VOLUME_ADJUSTMENT = "-96".freeze

    def to_xml
      raise ArgumentError, "No clips provided" if clips.empty?

      timeline_frame_duration = format_frame_duration
      timeline_clips, sequence_duration = build_timeline_clips(asset_map, timeline_frame_duration)

      event_uid = generate_uuid
      project_uid = generate_uuid

      first_path = clips.first[:path]
      first_filename = get_filename(first_path)
      project_basename = get_basename(first_filename)
      timestamped_project_name = "#{project_basename} #{timestamp_suffix}"

      still_format_ids = build_still_format_ids(asset_map)
      video_format_ids = build_video_format_ids(asset_map)

      builder = Nokogiri::XML::Builder.new(encoding: 'utf-8') do |xml|
        xml.fcpxml(version: '1.12') do
          xml.resources do
            xml.format(
              id: FORMAT_ID,
              height: format_height,
              width: format_width,
              frameDuration: format_frame_duration,
              colorSpace: format_color_space
            )

            # Sources that don't match the timeline format get their own
            # format resource, so Final Cut sees each asset's real dimensions,
            # frame rate, and color space instead of the timeline's.
            video_format_ids.each do |(width, height, frame_duration, color_space), format_id|
              next if format_id == FORMAT_ID

              xml.format(
                id: format_id,
                height: height,
                width: width,
                frameDuration: frame_duration,
                colorSpace: color_space
              )
            end

            # Stills use a rate-undefined format (one per unique dimensions):
            # no frameDuration — that's what marks the asset as timeless.
            still_format_ids.each do |(width, height), format_id|
              xml.format(
                id: format_id,
                name: 'FFVideoFormatRateUndefined',
                width: width,
                height: height
              )
            end

            # Since fcpxml 1.9 an asset points at its file through a
            # media-rep child, not a src attribute.
            asset_map.each_value do |asset|
              if asset[:type] == 'image'
                # Timeless still: duration/start pinned to 0s, video only —
                # no audio attributes at all.
                xml.asset(
                  id: asset[:asset_id],
                  name: asset[:filename],
                  uid: asset[:asset_uid],
                  start: '0s',
                  duration: '0s',
                  hasVideo: '1',
                  format: still_format_ids.fetch([asset[:width], asset[:height]])
                ) do
                  xml.send('media-rep', kind: 'original-media', src: asset[:file_url])
                end
              else
                xml.asset(
                  id: asset[:asset_id],
                  name: asset[:filename],
                  uid: asset[:asset_uid],
                  start: asset[:timecode],
                  audioRate: asset[:audio_rate],
                  hasAudio: '1',
                  hasVideo: '1',
                  format: video_format_ids.fetch(video_format_key(asset)),
                  duration: asset[:asset_duration]
                ) do
                  xml.send('media-rep', kind: 'original-media', src: asset[:file_url])
                end
              end
            end

            emit_extra_resources(xml, asset_map, timeline_frame_duration)
          end

          xml.library(location: './') do
            xml.event(name: project_basename, uid: event_uid) do
              xml.project(name: timestamped_project_name, uid: project_uid, modDate: '2025-10-31 17:25:16 GMT-7') do
                xml.sequence(duration: sequence_duration, format: FORMAT_ID, tcStart: '0s', audioRate: '48k') do
                  xml.spine do
                    emit_spine(xml, timeline_clips)
                  end
                end
              end
            end
          end
        end
      end

      builder.to_xml
    end

    # Final Cut measures every value inside a sequence against the SEQUENCE's
    # frame grid, never the source's. A clip whose rate differs from the
    # timeline's — 23.976 footage on a 24p sequence, the rate the first clip
    # set — lands its source-anchored start between sequence frames, and Final
    # Cut answers with "The item is not on an edit frame boundary" on import
    # and leaves 1-frame crumbs at the tail of the timeline (a 32s cut arrives
    # 32:03 long). Snap the start to the nearest sequence frame, but never
    # earlier than the media's own first frame: half a frame before the head
    # still points at footage that doesn't exist.
    #
    # That snap can only move a start LATER, and the duration was measured from
    # the unsnapped one — an untrimmed conformed clip would read a whole
    # sequence frame past its own media (and even unsnapped, rounding the
    # media's length to the grid can overrun it by a fraction of a frame). So
    # the duration is capped at what the media has left after the start.
    #
    # Same-rate media is already on the grid, so every same-rate export comes
    # through untouched.
    def build_standard_clip_data(clip_def, asset_map, current_offset, timeline_frame_duration)
      data = super
      asset = data[:asset]
      return data unless asset[:asset_duration]

      start = [fraction_to_rational(round_to_frame_boundary(data[:start], timeline_frame_duration)),
               fraction_to_rational(media_head(asset, timeline_frame_duration))].max
      remaining = media_end(asset) - start

      duration = data[:duration]
      duration = floor_to_frame_boundary(rational_to_fraction(remaining), timeline_frame_duration) if
        remaining.positive? && fraction_to_rational(duration) > remaining

      data.merge(start: rational_to_fraction(start), duration: duration)
    end

    # The media's own first frame, on the sequence's grid: the first whole
    # sequence frame AT OR AFTER its source timecode. Rounding down would open
    # a clip on a frame the media doesn't have.
    def media_head(asset, timeline_frame_duration)
      ceil_to_frame_boundary(asset[:timecode] || '0s', timeline_frame_duration)
    end

    # ...and where that media runs out, at wire precision.
    def media_end(asset)
      fraction_to_rational(asset[:timecode] || '0s') + fraction_to_rational(asset[:asset_duration])
    end

    private

    # Extra resources an edition wants inside <resources> — nothing here.
    # A seam like emit_spine: an edition variant overrides it to add its own
    # resource elements (e.g. media/multicam) while inheriting to_xml.
    def emit_extra_resources(xml, asset_map, timeline_frame_duration); end

    # Emit the timeline onto the spine: one clip after another, in order.
    # This is the seam edition variants override — a multi-track edition
    # replaces it (V1 spine plus connected clips on lanes) while inheriting
    # the rest of to_xml unchanged.
    def emit_spine(xml, timeline_clips)
      timeline_clips.each { |clip| emit_spine_clip(xml, clip) }
    end

    # Render one clip on the spine. Stills go on as <video> (timeless, no
    # audio → no adjust-volume child); video clips go on as <asset-clip> with
    # a dialogue role. `lane:`, `offset:`, and the block place connected
    # clips — the single-track spine passes none of them; they exist for a
    # multi-track emit_spine override to hook into.
    def emit_spine_clip(xml, clip, lane: nil, offset: nil)
      still = clip[:asset][:type] == 'image'
      video_only = still || video_only_clip?(clip)
      attrs = {
        name: clip[:filename],
        ref: clip[:asset_id],
        start: still ? '0s' : clip[:start],
        offset: offset || clip[:timeline_offset],
        duration: clip[:duration]
      }
      attrs[:audioRole] = 'dialogue' unless video_only
      attrs[:lane] = lane if lane

      if video_only
        # No audio → no adjust-volume child; stay self-closing when there are
        # no connected clips to nest.
        block_given? ? xml.video(**attrs) { yield } : xml.video(**attrs)
      else
        xml.send('asset-clip', **attrs) do
          xml.send('adjust-volume', amount: clip_volume_adjustment(clip))
          yield if block_given?
        end
      end
    end

    # Whether a clip with an audio-bearing asset sheds its audio component and
    # rides the spine as a <video> element — never here. A seam: an edition
    # variant can make silence structural, for importers that ignore
    # <adjust-volume>.
    def video_only_clip?(_clip) = false

    # The adjust-volume amount for a clip: silence if muted, otherwise the
    # base trim level.
    def clip_volume_adjustment(clip)
      return MUTE_VOLUME_ADJUSTMENT if clip.dig(:clip_definition, :mute)

      volume_adjustment
    end

    # One format resource per distinct video spec, keyed
    # [width, height, frame duration, color space] → format id. Assets whose
    # spec matches the timeline format reuse it (FORMAT_ID), keeping the
    # common single-source-format export unchanged.
    def build_video_format_ids(asset_map)
      timeline_key = [format_width, format_height, format_frame_duration, format_color_space]
      asset_map.each_value.with_object(timeline_key => FORMAT_ID) do |asset, ids|
        next if asset[:type] == 'image'

        ids[video_format_key(asset)] ||= video_format_id(asset)
      end
    end

    # The key and id use DISPLAY dimensions — a quarter-turn source swaps its
    # stored frame. Final Cut and Resolve rotate the pixels upright from the
    # source flag themselves, but they trust the declared format, so upright
    # and rotated sources of the same stored frame stay distinct formats.
    def video_format_key(asset)
      width, height = display_dimensions(asset)
      [width, height, asset[:frame_duration], asset[:color_space]]
    end

    # Deterministic, human-readable id: "r_fmt_3840x2160_1000_30000_9-1-9".
    def video_format_id(asset)
      width, height = display_dimensions(asset)
      rate = asset[:frame_duration].delete_suffix('s').tr('/', '_')
      color = asset[:color_space][/[\d-]+/]
      "r_fmt_#{width}x#{height}_#{rate}_#{color}"
    end

    # One rate-undefined format resource per unique still dimensions, keyed
    # [width, height] → format id.
    def build_still_format_ids(asset_map)
      asset_map.each_value.with_object({}) do |asset, ids|
        next unless asset[:type] == 'image'

        key = [asset[:width], asset[:height]]
        ids[key] ||= "r_still_#{asset[:width]}x#{asset[:height]}"
      end
    end
  end
end
