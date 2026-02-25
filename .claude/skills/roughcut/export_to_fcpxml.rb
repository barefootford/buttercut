#!/usr/bin/env ruby
# Export rough cut YAML to Final Cut Pro XML using ButterCut

require 'date'
require 'yaml'
require 'buttercut'

def timecode_to_seconds(timecode)
  # Convert HH:MM:SS or HH:MM:SS.s to seconds (supports decimal seconds)
  parts = timecode.split(':')
  hours = parts[0].to_i
  minutes = parts[1].to_i
  seconds = parts[2].to_f  # to_f handles both "03" and "03.5"
  hours * 3600 + minutes * 60 + seconds
end

def main
  if ARGV.length < 2
    puts "Usage: #{$0} <roughcut.yaml> <output.xml> [editor] [sequence_fps] [width] [height] [options]"
    puts "  editor: fcpx (default), premiere, or resolve"
    puts "  sequence_fps: override sequence frame rate (e.g., 50 for 50fps)"
    puts "  width/height: sequence dimensions (e.g., 1080 1920 for portrait)"
    puts "  --windows-file-paths: convert Linux/WSL paths to Windows format (e.g., /mnt/d/ -> D:/)"
    puts "  --audio <file>: add audio/music track to the sequence (trimmed to fit)"
    exit 1
  end

  # Check for --windows-file-paths flag anywhere in args
  windows_file_paths = ARGV.include?('--windows-file-paths')

  # Check for --audio flag and extract the audio file path
  audio_track = nil
  audio_index = ARGV.index('--audio')
  if audio_index && ARGV[audio_index + 1]
    audio_track = ARGV[audio_index + 1]
    unless File.exist?(audio_track)
      puts "Error: Audio file not found: #{audio_track}"
      exit 1
    end
  end

  # Remove flags from args to get positional arguments
  args = ARGV.reject.with_index { |a, i| a == '--windows-file-paths' || a == '--audio' || (audio_index && i == audio_index + 1) }

  roughcut_path = args[0]
  output_path = args[1]
  editor_choice = args[2] || 'fcpx'
  sequence_fps = args[3] ? args[3].to_i : nil
  sequence_width = args[4] ? args[4].to_i : nil
  sequence_height = args[5] ? args[5].to_i : nil

  unless File.exist?(roughcut_path)
    puts "Error: Rough cut file not found: #{roughcut_path}"
    exit 1
  end

  # Load rough cut YAML
  roughcut = YAML.load_file(roughcut_path, permitted_classes: [Date, Time, Symbol])

  # Find library name from path
  # Path pattern: libraries/[library-name]/roughcuts/[roughcut-name].yaml
  library_match = roughcut_path.match(%r{libraries/([^/]+)/roughcuts})
  unless library_match
    puts "Error: Could not extract library name from path: #{roughcut_path}"
    exit 1
  end
  library_name = library_match[1]

  # Load library file to get full video paths
  library_yaml = "libraries/#{library_name}/library.yaml"
  unless File.exist?(library_yaml)
    puts "Error: Library file not found: #{library_yaml}"
    exit 1
  end

  library_data = YAML.load_file(library_yaml, permitted_classes: [Date, Time, Symbol])

  # Build lookup map: filename -> full path
  video_paths = {}
  library_data['videos'].each do |video|
    filename = File.basename(video['path'])
    video_paths[filename] = video['path']
  end

  # Convert rough cut clips to ButterCut format
  buttercut_clips = []

  roughcut['clips'].each do |clip|
    source_file = clip['source_file']

    unless video_paths[source_file]
      puts "Warning: Source file not found in library data: #{source_file}"
      next
    end

    full_path = video_paths[source_file]
    start_at = timecode_to_seconds(clip['in_point'])
    out_point = timecode_to_seconds(clip['out_point'])
    duration = out_point - start_at

    clip_hash = {
      path: full_path,
      start_at: start_at.to_f,
      duration: duration.to_f
    }
    clip_hash[:speed] = clip['speed'].to_f if clip['speed']
    clip_hash[:rotation] = clip['rotation'].to_i if clip['rotation']
    buttercut_clips << clip_hash
  end

  # Validate and normalize editor choice
  editor_symbol = case editor_choice.downcase
  when 'fcpx', 'finalcutpro', 'finalcut', 'fcp'
    :fcpx
  when 'premiere', 'premierepro', 'adobepremiere'
    :fcp7
  when 'resolve', 'davinci', 'davinciresolve'
    :fcp7
  else
    puts "Error: Unknown editor '#{editor_choice}'. Use 'fcpx', 'premiere', or 'resolve'"
    exit 1
  end

  editor_name = editor_symbol == :fcpx ? "Final Cut Pro X" : "#{editor_choice.capitalize}"

  fps_msg = sequence_fps ? " (#{sequence_fps}fps" : ""
  dim_msg = sequence_width && sequence_height ? " #{sequence_width}x#{sequence_height}" : ""
  fps_msg += "#{dim_msg})" if fps_msg != "" || dim_msg != ""
  audio_msg = audio_track ? " + audio: #{File.basename(audio_track)}" : ""
  puts "Converting #{buttercut_clips.length} clips to #{editor_name} XML#{fps_msg}#{audio_msg}..."

  options = { editor: editor_symbol }
  options[:sequence_frame_rate] = sequence_fps if sequence_fps
  options[:sequence_width] = sequence_width if sequence_width
  options[:sequence_height] = sequence_height if sequence_height
  options[:windows_file_paths] = windows_file_paths
  options[:audio_track] = audio_track if audio_track
  options[:audio_start] = roughcut['audio_start'] if roughcut['audio_start']

  generator = ButterCut.new(buttercut_clips, **options)
  generator.save(output_path)

  puts "\n✓ Rough cut exported to: #{output_path}"
end

main
