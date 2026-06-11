require_relative 'editor_base'
require 'nokogiri'

class ButterCut
  # Final Cut Pro X (FCPXML 1.8) implementation.
  class FCPX < EditorBase
    FORMAT_ID = "r1".freeze

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

      builder = Nokogiri::XML::Builder.new(encoding: 'utf-8') do |xml|
        xml.fcpxml(version: '1.8') do
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

            asset_map.each_value do |asset|
              if asset[:type] == 'image'
                # Timeless still: duration/start pinned to 0s, video only —
                # no audio attributes at all.
                xml.asset(
                  id: asset[:asset_id],
                  name: asset[:filename],
                  uid: asset[:asset_uid],
                  src: asset[:file_url],
                  start: '0s',
                  duration: '0s',
                  hasVideo: '1',
                  format: still_format_ids.fetch([asset[:width], asset[:height]])
                )
              else
                xml.asset(
                  id: asset[:asset_id],
                  name: asset[:filename],
                  uid: asset[:asset_uid],
                  src: asset[:file_url],
                  start: asset[:timecode],
                  audioRate: asset[:audio_rate],
                  hasAudio: '1',
                  hasVideo: '1',
                  format: FORMAT_ID,
                  duration: asset[:asset_duration]
                )
              end
            end
          end

          xml.library(location: './') do
            xml.event(name: project_basename, uid: event_uid) do
              xml.project(name: timestamped_project_name, uid: project_uid, modDate: '2025-10-31 17:25:16 GMT-7') do
                xml.sequence(duration: sequence_duration, format: FORMAT_ID, tcStart: '0s', audioRate: '48k') do
                  xml.spine do
                    timeline_clips.each do |clip|
                      if clip[:asset][:type] == 'image'
                        # Stills go on the spine as <video>, not <asset-clip>:
                        # an asset-clip's duration defaults to the asset's,
                        # which is 0s for a timeless still. No audio → no
                        # adjust-volume child.
                        xml.video(
                          name: clip[:filename],
                          ref: clip[:asset_id],
                          start: '0s',
                          offset: clip[:timeline_offset],
                          duration: clip[:duration]
                        )
                      else
                        xml.send('asset-clip',
                          name: clip[:filename],
                          ref: clip[:asset_id],
                          start: clip[:start],
                          offset: clip[:timeline_offset],
                          duration: clip[:duration],
                          audioRole: 'dialogue'
                        ) do
                          xml.send('adjust-volume', amount: volume_adjustment)
                        end
                      end
                    end
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
