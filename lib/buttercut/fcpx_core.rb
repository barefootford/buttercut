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
      @native_format_ids = build_native_format_ids(asset_map, timeline_frame_duration)
      sequence_tc_format = @native_format_ids.empty? ? nil : 'NDF'

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

            # Per-asset native-rate formats: only emitted when a clip's own
            # frame rate differs from the sequence's — e.g. Final Cut
            # Camera's iPhone footage, which tags itself as a 29.97 drop-
            # frame project while the actual media is flat 30fps. Final Cut
            # cross-checks an asset-clip's declared rate against the file's
            # own embedded timing on import; reusing the sequence's format
            # for a mismatched clip gets the edit rejected ("Invalid edit
            # with no respective media"), which is exactly the failure mode
            # this fixes.
            @native_format_ids.each_value do |entry|
              xml.format(
                id: entry[:id],
                frameDuration: entry[:frame_duration],
                width: format_width,
                height: format_height,
                colorSpace: format_color_space
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
                native_entry = @native_format_ids[asset[:frame_duration]]
                xml.asset(
                  id: asset[:asset_id],
                  name: asset[:filename],
                  uid: asset[:asset_uid],
                  start: asset[:timecode],
                  audioRate: asset[:audio_rate],
                  hasAudio: '1',
                  hasVideo: '1',
                  format: native_entry ? native_entry[:id] : FORMAT_ID,
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
                sequence_attrs = { duration: sequence_duration, format: FORMAT_ID, tcStart: '0s', audioRate: '48k' }
                sequence_attrs[:tcFormat] = sequence_tc_format if sequence_tc_format
                xml.sequence(**sequence_attrs) do
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

      # A clip whose native rate differs from the sequence's (see
      # `build_native_format_ids`) needs to point at its own format resource
      # and tell Final Cut how to conform it — otherwise the asset-clip's
      # declared timing silently disagrees with the file's own embedded
      # rate and Final Cut rejects the edit on import. (tcFormat is valid
      # per the FCPXML 1.12 DTD but Final Cut's own importer flags it as an
      # unexpected value on asset-clip at this version, so it's omitted here
      # — the format + conform-rate pairing is what actually fixes import.)
      native_entry = !still && @native_format_ids[clip[:asset][:frame_duration]]
      attrs[:format] = native_entry[:id] if native_entry

      if still
        # No audio → no adjust-volume child; stay self-closing when there are
        # no connected clips to nest.
        block_given? ? xml.video(**attrs) { yield } : xml.video(**attrs)
      else
        xml.send('asset-clip', **attrs) do
          if native_entry
            xml.send('conform-rate', srcFrameRate: clip[:asset][:nominal_frame_rate].to_s)
          end
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

    # One rate-undefined format resource per unique still dimensions, keyed
    # [width, height] → format id.
    def build_still_format_ids(asset_map)
      asset_map.each_value.with_object({}) do |asset, ids|
        next unless asset[:type] == 'image'

        key = [asset[:width], asset[:height]]
        ids[key] ||= "r_still_#{asset[:width]}x#{asset[:height]}"
      end
    end

    # One extra format resource per unique native frame rate that differs
    # from the sequence's own — keyed by the asset's `frame_duration` string
    # (e.g. "1/30s") → {id:, frame_duration:}. Empty for the common case
    # where every clip already matches the sequence rate, so this changes
    # nothing about existing single-rate cuts.
    def build_native_format_ids(asset_map, timeline_frame_duration)
      asset_map.each_value.with_object({}) do |asset, ids|
        next if asset[:type] == 'image'
        next if asset[:frame_duration].nil? || asset[:frame_duration] == timeline_frame_duration
        next if ids.key?(asset[:frame_duration])

        ids[asset[:frame_duration]] = {
          id: "r_native_#{ids.size + 1}",
          frame_duration: asset[:frame_duration]
        }
      end
    end
  end
end
