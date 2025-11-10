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
      event_name = project_basename
      timestamped_project_name = "#{project_basename} #{timestamp_suffix}"

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

            asset_map.each_value do |asset|
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

          xml.library(location: './') do
            xml.event(name: event_name, uid: event_uid) do
              xml.project(name: timestamped_project_name, uid: project_uid, modDate: '2025-10-31 17:25:16 GMT-7') do
                xml.sequence(duration: sequence_duration, format: FORMAT_ID, tcStart: '0s', audioRate: '48k') do
                  xml.spine do
                    timeline_clips.each do |clip|
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

      builder.to_xml
    end
  end
end
