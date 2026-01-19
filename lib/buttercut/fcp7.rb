require_relative 'editor_base'
require 'nokogiri'

class ButterCut
  # Final Cut Pro 7 XML Interchange Format (version 5).
  # This structure can be imported by legacy FCP as well as Adobe Premiere Pro.
  class FCP7 < EditorBase
    def to_xml
      raise ArgumentError, "No clips provided" if clips.empty?

      asset_map = build_asset_map
      timeline_frame_duration = format_frame_duration
      timeline_clips, sequence_duration_fraction = build_timeline_clips(asset_map, timeline_frame_duration)

      rate_num, rate_denom = format_frame_rate.split('/').map(&:to_i)
      timebase = format_nominal_frame_rate
      ntsc_flag = ntsc_flag_for(rate_denom)
      drop_frame = drop_frame_rate?(rate_num, rate_denom)
      display_format = drop_frame ? 'DF' : 'NDF'

      sequence_duration_frames = frames_for_fraction(sequence_duration_fraction, timeline_frame_duration)
      sequence_uuid = generate_uuid
      sequence_id = "sequence-#{sequence_uuid}"

      first_path = clips.first[:path]
      sequence_name = "#{get_basename(get_filename(first_path))} #{timestamp_suffix}"

      clip_payloads = build_clip_payloads(timeline_clips, timeline_frame_duration)
      sequence_audio_rate = format_audio_rate || '48000'

      builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml.doc.create_internal_subset('xmeml', nil, nil)
        xml.xmeml(version: '5') do
          xml.sequence(id: sequence_id) do
            xml.uuid sequence_uuid
            xml.name sequence_name
            xml.duration sequence_duration_frames
            xml.rate do
              xml.timebase timebase
              xml.ntsc ntsc_flag
            end
            xml.in 0
            xml.out sequence_duration_frames
            xml.timecode do
              xml.rate do
                xml.timebase timebase
                xml.ntsc ntsc_flag
              end
              xml.frame 0
              xml.displayformat display_format
            end
            xml.media do
              xml.video do
                xml.format do
                  xml.samplecharacteristics do
                    xml.rate do
                      xml.timebase timebase
                      xml.ntsc ntsc_flag
                    end
                    xml.width format_width
                    xml.height format_height
                    xml.anamorphic 'FALSE'
                    xml.pixelaspectratio 'square'
                    xml.fielddominance 'none'
                  end
                end
                xml.track do
                  clip_payloads.each do |payload|
                    build_video_clipitem(xml, payload)
                  end
                end
              end
              xml.audio do
                xml.numOutputChannels 2
                xml.format do
                  xml.samplecharacteristics do
                    xml.samplerate sequence_audio_rate
                    xml.sampledepth 16
                  end
                end
                xml.track do
                  clip_payloads.each do |payload|
                    build_audio_clipitem(xml, payload)
                  end
                end
                # Add music track if audio_track option is provided
                if audio_track
                  xml.track do
                    build_music_track(xml, sequence_duration_frames, timebase, ntsc_flag, sequence_audio_rate)
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

    def ntsc_flag_for(rate_denom)
      rate_denom == 1 ? 'FALSE' : 'TRUE'
    end

    def drop_frame_rate?(rate_num, rate_denom)
      (rate_num == 30000 && rate_denom == 1001) || (rate_num == 60000 && rate_denom == 1001)
    end

    def build_clip_payloads(timeline_clips, timeline_frame_duration)
      timeline_clips.each_with_index.map do |clip, index|
        asset = clip[:asset]
        asset_rate_num, asset_rate_denom = asset[:frame_rate].split('/').map(&:to_i)
        asset_timebase = (asset_rate_num.to_f / asset_rate_denom).round
        asset_ntsc = ntsc_flag_for(asset_rate_denom)
        asset_display = drop_frame_rate?(asset_rate_num, asset_rate_denom) ? 'DF' : 'NDF'

        timeline_duration_frames = frames_for_fraction(clip[:duration], timeline_frame_duration)
        timeline_start_frames = frames_for_fraction(clip[:timeline_offset], timeline_frame_duration)
        timeline_end_frames = timeline_start_frames + timeline_duration_frames

        source_in_frames = frames_for_fraction(clip[:source_in], asset[:frame_duration])
        source_duration_frames = frames_for_fraction(clip[:source_duration], asset[:frame_duration])
        source_out_frames = source_in_frames + source_duration_frames

        asset_duration_frames = frames_for_fraction(asset[:asset_duration], asset[:frame_duration])
        asset_timecode_start = frames_for_fraction(asset[:timecode], asset[:frame_duration])

        {
          index: index + 1,
          clip: clip,
          asset: asset,
          video_clip_id: "clipitem-video-#{index + 1}",
          audio_clip_id: "clipitem-audio-#{index + 1}",
          file_id: "file-#{asset[:asset_id]}",
          timeline_start: timeline_start_frames,
          timeline_end: timeline_end_frames,
          timeline_duration: timeline_duration_frames,
          source_in: source_in_frames,
          source_out: source_out_frames,
          source_duration_frames: source_duration_frames,
          asset_timebase: asset_timebase,
          asset_ntsc: asset_ntsc,
          asset_display: asset_display,
          asset_duration_frames: asset_duration_frames,
          asset_timecode_start: asset_timecode_start
        }
      end
    end

    def build_video_clipitem(xml, payload)
      asset = payload[:asset]

      xml.clipitem(id: payload[:video_clip_id]) do
        xml.name asset[:basename]
        xml.enabled 'TRUE'
        xml.duration payload[:timeline_duration]
        xml.start payload[:timeline_start]
        xml.end_ payload[:timeline_end]
        xml.in_ payload[:source_in]
        xml.out payload[:source_out]
        xml.file(id: payload[:file_id]) do
          xml.name asset[:filename]
          xml.pathurl asset[:file_url]
          xml.rate do
            xml.timebase payload[:asset_timebase]
            xml.ntsc payload[:asset_ntsc]
          end
          xml.duration payload[:asset_duration_frames]
          xml.timecode do
            xml.rate do
              xml.timebase payload[:asset_timebase]
              xml.ntsc payload[:asset_ntsc]
            end
            xml.frame payload[:asset_timecode_start]
            xml.displayformat payload[:asset_display]
          end
          xml.media do
            xml.video do
              xml.samplecharacteristics do
                xml.rate do
                  xml.timebase payload[:asset_timebase]
                  xml.ntsc payload[:asset_ntsc]
                end
                xml.width asset[:width]
                xml.height asset[:height]
                xml.anamorphic 'FALSE'
                xml.pixelaspectratio 'square'
                xml.fielddominance 'none'
              end
            end
            xml.audio do
              xml.samplecharacteristics do
                xml.samplerate asset_audio_rate(asset)
                xml.sampledepth 16
              end
            end
          end
        end
        xml.sourcetrack do
          xml.mediatype 'video'
          xml.trackindex 1
        end
        build_motion_filter(xml, payload) if needs_motion_filter?(payload)
        build_link_entries(xml, payload)
      end
    end

    def needs_motion_filter?(payload)
      asset = payload[:asset]
      rotation = asset[:rotation] || 0

      # Need motion filter if:
      # 1. Clip has rotation metadata (portrait video)
      # 2. Clip dimensions don't match sequence dimensions
      return true if rotation != 0

      seq_width = format_width
      seq_height = format_height
      clip_width = asset[:width]
      clip_height = asset[:height]

      # If sequence is portrait (height > width) and clip is landscape, need to scale
      seq_is_portrait = seq_height > seq_width
      clip_is_landscape = clip_width > clip_height

      seq_is_portrait && clip_is_landscape
    end

    def build_motion_filter(xml, payload)
      asset = payload[:asset]
      rotation = asset[:rotation] || 0
      clip_width = asset[:width].to_f
      clip_height = asset[:height].to_f
      seq_width = format_width.to_f
      seq_height = format_height.to_f

      # Calculate effective dimensions after rotation and determine FCP rotation value
      # Video metadata rotation indicates clockwise rotation needed to display correctly
      # FCP7 uses: positive = counter-clockwise, negative = clockwise
      # So we negate the metadata value for FCP7
      if rotation == 90
        effective_width = clip_height
        effective_height = clip_width
        fcp_rotation = -90  # Apply 90° clockwise in FCP7
      elsif rotation == 270 || rotation == -90
        effective_width = clip_height
        effective_height = clip_width
        fcp_rotation = 90   # Apply 90° counter-clockwise in FCP7
      else
        effective_width = clip_width
        effective_height = clip_height
        fcp_rotation = 0
      end

      # Determine scaling mode based on aspect ratios
      seq_is_portrait = seq_height > seq_width
      clip_is_landscape = effective_width > effective_height

      scale_x = seq_width / effective_width
      scale_y = seq_height / effective_height

      if seq_is_portrait && clip_is_landscape
        # Landscape clip in portrait sequence: fill height, crop sides (center crop)
        scale = scale_y * 100
      else
        # Default: fit mode (letterbox)
        scale = [scale_x, scale_y].min * 100
      end

      xml.filter do
        xml.effect do
          xml.name 'Basic Motion'
          xml.effectid 'basic'
          xml.effectcategory 'motion'
          xml.effecttype 'motion'
          xml.mediatype 'video'
          xml.pproBypass 'false'

          # Scale parameter
          xml.parameter do
            xml.parameterid 'scale'
            xml.name 'Scale'
            xml.valuemin 0
            xml.valuemax 1000
            xml.value scale.round(2)
          end

          # Rotation parameter (only if needed)
          if fcp_rotation != 0
            xml.parameter do
              xml.parameterid 'rotation'
              xml.name 'Rotation'
              xml.valuemin(-8640)
              xml.valuemax 8640
              xml.value fcp_rotation
            end
          end

          # Center parameter (keep centered)
          xml.parameter do
            xml.parameterid 'center'
            xml.name 'Center'
            xml.value do
              xml.horiz 0
              xml.vert 0
            end
          end
        end
      end
    end

    def build_audio_clipitem(xml, payload)
      asset = payload[:asset]

      xml.clipitem(id: payload[:audio_clip_id]) do
        xml.name asset[:basename]
        xml.enabled 'TRUE'
        xml.duration payload[:timeline_duration]
        xml.start payload[:timeline_start]
        xml.end_ payload[:timeline_end]
        xml.in_ payload[:source_in]
        xml.out payload[:source_out]
        xml.file(id: payload[:file_id]) do
          xml.name asset[:filename]
          xml.pathurl asset[:file_url]
          xml.rate do
            xml.timebase payload[:asset_timebase]
            xml.ntsc payload[:asset_ntsc]
          end
          xml.duration payload[:asset_duration_frames]
          xml.media do
            xml.audio do
              xml.samplecharacteristics do
                xml.samplerate asset_audio_rate(asset)
                xml.sampledepth 16
              end
            end
          end
        end
        xml.sourcetrack do
          xml.mediatype 'audio'
          xml.trackindex 1
        end
        xml.channelcount 2
        build_link_entries(xml, payload)
      end
    end

    def build_link_entries(xml, payload)
      xml.link do
        xml.linkclipref payload[:video_clip_id]
        xml.mediatype 'video'
        xml.trackindex 1
        xml.clipindex payload[:index]
      end
      xml.link do
        xml.linkclipref payload[:audio_clip_id]
        xml.mediatype 'audio'
        xml.trackindex 1
        xml.clipindex payload[:index]
        xml.groupindex 1
      end
    end

    def asset_audio_rate(asset)
      asset[:audio_rate] || format_audio_rate || '48000'
    end

    def build_music_track(xml, sequence_duration_frames, timebase, ntsc_flag, sequence_audio_rate)
      music_path = audio_track
      music_filename = get_filename(music_path)
      music_basename = get_basename(music_filename)
      music_file_url = path_to_file_url(music_path)
      music_sample_rate = audio_sample_rate(music_path)

      # Calculate music duration in frames
      timeline_frame_duration = format_frame_duration
      music_duration_fraction = audio_duration_to_fraction(music_path, timeline_frame_duration)
      music_duration_frames = frames_for_fraction(music_duration_fraction, timeline_frame_duration)

      # Trim music to sequence length if longer
      effective_duration = [music_duration_frames, sequence_duration_frames].min
      music_file_id = "file-music-#{deterministic_asset_id(get_absolute_path(music_path))}"

      xml.clipitem(id: 'clipitem-music-1') do
        xml.name music_basename
        xml.enabled 'TRUE'
        xml.duration effective_duration
        xml.start 0
        xml.end_ effective_duration
        xml.in_ 0
        xml.out effective_duration
        xml.file(id: music_file_id) do
          xml.name music_filename
          xml.pathurl music_file_url
          xml.rate do
            xml.timebase timebase
            xml.ntsc ntsc_flag
          end
          xml.duration music_duration_frames
          xml.media do
            xml.audio do
              xml.samplecharacteristics do
                xml.samplerate music_sample_rate
                xml.sampledepth 16
              end
            end
          end
        end
        xml.sourcetrack do
          xml.mediatype 'audio'
          xml.trackindex 1
        end
        xml.channelcount 2
      end
    end
  end
end
