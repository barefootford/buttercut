module Buttercut
  # Compresses WhisperX JSON transcripts into a compact pipe-delimited text format
  # Reduces token usage by 60-80% while maintaining human readability
  class TranscriptCompressor
    VERSION = "1.0"

    # Convert WhisperX JSON to compressed format
    # @param json_data [Hash] Parsed WhisperX JSON
    # @param include_words [Boolean] Include word-level timing (for audio transcripts)
    # @return [String] Compressed transcript
    def self.compress(json_data, include_words: true)
      lines = []

      # Header: @video_path|language
      video_path = json_data['video_path'] || ''
      language = json_data['language'] || 'en'
      lines << "@#{video_path}|#{language}"
      lines << ""

      # Process segments
      segments = json_data['segments'] || []
      segments.each do |segment|
        start_time = format_time(segment['start'])
        end_time = format_time(segment['end'])
        text = segment['text']&.strip || ''

        # B-roll segments use 'b:' prefix, regular segments use '#'
        if segment['b_roll']
          lines << "b: #{start_time}-#{end_time} | #{text}"
          if segment['visual']
            lines << "  #{segment['visual']}"
          end
        else
          lines << "# #{start_time}-#{end_time} | #{text}"
          if segment['visual']
            lines << "v: #{segment['visual']}"
          end
        end

        # Word-level timing if requested and available
        if include_words && segment['words'] && !segment['words'].empty?
          word_parts = segment['words'].map do |w|
            word = w['word'] || w['text'] || ''
            w_start = format_time(w['start'])
            w_end = format_time(w['end'])
            "#{word}|#{w_start}-#{w_end}"
          end
          lines << "w: #{word_parts.join(' ')}"
        end

        lines << ""
      end

      lines.join("\n")
    end

    # Convert compressed format back to JSON structure
    # @param compressed_text [String] Compressed transcript
    # @return [Hash] JSON-compatible hash
    def self.decompress(compressed_text)
      lines = compressed_text.split("\n")

      # Parse header
      header = lines.shift&.strip || ''
      unless header.start_with?('@')
        raise "Invalid format: missing header line"
      end

      parts = header[1..-1].split('|')
      video_path = parts[0] || ''
      language = parts[1] || 'en'

      # Build result structure
      result = {
        'video_path' => video_path,
        'language' => language,
        'segments' => []
      }

      current_segment = nil

      lines.each do |line|
        # Check for indented lines (b-roll visuals) before stripping
        is_indented = line.start_with?(' ', "\t")
        line_stripped = line.strip
        next if line_stripped.empty?

        if line_stripped.start_with?('#') || line_stripped.start_with?('b:')
          # New segment
          is_broll = line_stripped.start_with?('b:')
          line_content = line_stripped[2..-1].strip

          time_and_text = line_content.split('|', 2)
          time_range = time_and_text[0]&.strip || ''
          text = time_and_text[1]&.strip || ''

          times = time_range.split('-')
          start_time = parse_time(times[0])
          end_time = parse_time(times[1])

          current_segment = {
            'start' => start_time,
            'end' => end_time,
            'text' => text
          }

          current_segment['b_roll'] = true if is_broll
          result['segments'] << current_segment

        elsif line_stripped.start_with?('v:')
          # Visual description
          if current_segment
            current_segment['visual'] = line_stripped[2..-1].strip
          end

        elsif is_indented && current_segment
          # Indented lines are b-roll visual descriptions
          current_segment['visual'] = line_stripped

        elsif line_stripped.start_with?('w:')
          # Word-level timing
          if current_segment
            words_data = line_stripped[2..-1].strip
            words = []

            words_data.split(' ').each do |word_part|
              parts = word_part.split('|')
              next if parts.length < 2

              word_text = parts[0]
              times = parts[1].split('-')

              words << {
                'word' => word_text,
                'start' => parse_time(times[0]),
                'end' => parse_time(times[1])
              }
            end

            current_segment['words'] = words
          end
        end
      end

      result
    end

    private

    # Format timestamp to 2 decimal places
    def self.format_time(seconds)
      return "0.00" if seconds.nil?
      format("%.2f", seconds.to_f)
    end

    # Parse timestamp string to float
    def self.parse_time(time_str)
      return 0.0 if time_str.nil? || time_str.empty?
      time_str.to_f
    end
  end
end
