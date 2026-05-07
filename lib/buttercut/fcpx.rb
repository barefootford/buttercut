require_relative 'editor_base'
require 'nokogiri'

class ButterCut
  # Final Cut Pro X (FCPXML 1.8) implementation.
  class FCPX < EditorBase
    FORMAT_ID = "r1".freeze
    BROLL_LANE = 1
    MUSIC_LANE = -1

    def to_xml
      raise ArgumentError, "No clips provided" if clips.empty?

      asset_map = build_asset_map
      timeline_frame_duration = format_frame_duration
      timeline_clips, sequence_duration = build_timeline_clips(asset_map, timeline_frame_duration)
      anchored_clips = build_anchored_clips(asset_map, timeline_frame_duration, timeline_clips)
      anchored_by_parent = anchored_clips.group_by { |c| c[:parent_spine_index] }

      event_uid = generate_uuid
      project_uid = generate_uuid

      first_path = a_roll_clip_defs.first[:path]
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
              build_asset(xml, asset)
            end
          end

          xml.library(location: './') do
            xml.event(name: event_name, uid: event_uid) do
              xml.project(name: timestamped_project_name, uid: project_uid, modDate: '2025-10-31 17:25:16 GMT-7') do
                xml.sequence(duration: sequence_duration, format: FORMAT_ID, tcStart: '0s', audioRate: '48k') do
                  xml.spine do
                    timeline_clips.each do |clip|
                      children = anchored_by_parent[clip[:spine_index]] || []
                      build_spine_clip(xml, clip, children)
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

    def build_asset(xml, asset)
      attrs = {
        id: asset[:asset_id],
        name: asset[:filename],
        uid: asset[:asset_uid],
        src: asset[:file_url],
        start: asset[:timecode],
        hasAudio: asset[:has_audio] ? '1' : '0',
        hasVideo: asset[:has_video] ? '1' : '0',
        duration: asset[:asset_duration]
      }
      attrs[:audioRate] = asset[:audio_rate] if asset[:audio_rate]
      attrs[:format] = FORMAT_ID if asset[:has_video]
      xml.asset(attrs)
    end

    def build_spine_clip(xml, clip, children)
      xml.send('asset-clip',
        name: clip[:filename],
        ref: clip[:asset_id],
        start: clip[:start],
        offset: clip[:timeline_offset],
        duration: clip[:duration],
        audioRole: 'dialogue'
      ) do
        xml.send('adjust-volume', amount: volume_adjustment)
        children.each { |child| build_anchored_clip(xml, child) }
      end
    end

    def build_anchored_clip(xml, clip)
      case clip[:track]
      when :b_roll
        xml.send('asset-clip',
          name: clip[:filename],
          ref: clip[:asset_id],
          lane: BROLL_LANE,
          start: clip[:start],
          offset: clip[:parent_local_offset],
          duration: clip[:duration],
          srcEnable: 'video'
        )
      when :music
        xml.send('asset-clip',
          name: clip[:filename],
          ref: clip[:asset_id],
          lane: MUSIC_LANE,
          start: clip[:start],
          offset: clip[:parent_local_offset],
          duration: clip[:duration],
          audioRole: 'music'
        ) do
          xml.send('adjust-volume', amount: MUSIC_VOLUME_ADJUSTMENT)
        end
      end
    end
  end
end
