require_relative 'fcpx'

class ButterCut
  # DaVinci Resolve timeline export. The XML is the FCPX generator's, unchanged
  # — Resolve reads FCPXML 1.12 — but the source-timecode anchor diverges.
  class Resolve < FCPX
    # Resolve reads timecode off the file with or without a track, and links an
    # import by matching pool timecode — a zero anchor lands every clip offline.
    def untracked_timecode_string(video_path)
      stream_timecode_string(video_path) || format_timecode_string(video_path)
    end

    def to_xml = super.tap { warn_about_conformed_clips }

    private

    # Resolve usually can't link a clip whose media frame rate differs from
    # the sequence's out of an FCPXML: the clip imports permanently offline
    # ("clips were not yet found") no matter where the media sits, and nothing
    # in the XML changes it (reproduced in Resolve 21). The xmeml export links
    # the identical mixed-rate cut perfectly, so point at it here rather than
    # let the editor meet a timeline of offline clips.
    def warn_about_conformed_clips
      conformed = conformed_clip_filenames
      return if conformed.empty?

      subject = conformed.length == 1 ? "#{conformed.first} runs" : "#{conformed.join(', ')} run"
      warn "Warning: #{subject} at a different frame rate than the timeline. DaVinci Resolve fails to link " \
           'most rate-conformed clips from an FCPXML — they import offline ("clips were not yet found") no ' \
           "matter where the media sits. #{conformed_clip_advice}"
    end

    # What to do about it. The legacy xmeml flavor links mixed frame rates
    # correctly; an edition whose cuts can hold things xmeml can't carry
    # overrides this with the options that actually apply.
    def conformed_clip_advice
      'Export this cut with `--editor resolve_legacy` instead: that flavor imports and links mixed frame ' \
        'rates correctly.'
    end

    # Sources whose own frame rate differs from the sequence's, read off the
    # asset records the export was built from (build_asset_map: one per unique
    # file, frame_duration on video only — stills and audio have no rate to
    # conform). The comparison is on the rates themselves, so 24/1 and
    # 24000/1000 are the same grid.
    def conformed_clip_filenames
      timeline_rate = fraction_to_rational(format_frame_duration)
      asset_map.each_value
               .select { |asset| asset[:frame_duration] && fraction_to_rational(asset[:frame_duration]) != timeline_rate }
               .map { |asset| asset[:filename] }
    end
  end
end
