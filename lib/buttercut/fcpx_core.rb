require_relative 'editor_base'
require 'nokogiri'

class ButterCut
  # Final Cut Pro X (FCPXML 1.12) implementation. 1.12 keeps the export
  # readable by DaVinci Resolve 19.1.1+ as well as Final Cut.
  class FCPX < EditorBase
    FORMAT_ID = "r1".freeze
    # adjust-volume amount that silences a clip outright (a muted clip).
    # -96 dB is below the audible floor — effectively off.
    MUTE_VOLUME_ADJUSTMENT = "-96db".freeze

    def to_xml
      raise ArgumentError, "No clips provided" if clips.empty?

      asset_map = build_asset_map
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

    private

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
      attrs = {
        name: clip[:filename],
        ref: clip[:asset_id],
        start: still ? '0s' : clip[:start],
        offset: offset || clip[:timeline_offset],
        duration: clip[:duration]
      }
      attrs[:audioRole] = 'dialogue' unless still
      attrs[:lane] = lane if lane

      if still
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

    def video_format_key(asset)
      [asset[:width], asset[:height], asset[:frame_duration], asset[:color_space]]
    end

    # Deterministic, human-readable id: "r_fmt_3840x2160_1000_30000_9-1-9".
    def video_format_id(asset)
      rate = asset[:frame_duration].delete_suffix('s').tr('/', '_')
      color = asset[:color_space][/[\d-]+/]
      "r_fmt_#{asset[:width]}x#{asset[:height]}_#{rate}_#{color}"
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
