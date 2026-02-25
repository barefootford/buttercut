#!/usr/bin/env ruby
# Export detected scenes YAML to XML using ButterCut.
# Reads source_video from the scenes YAML directly — no library.yaml needed.
#
# All output goes into a buttercut/ subfolder next to the source video files:
#   <source_video_dir>/buttercut/scenes_C1605.yaml
#   <source_video_dir>/buttercut/xml/C1605_scene_01_20260207_1530.xml
#
# Usage:
#   ruby export_scenes.rb <scenes.yaml|"glob"> [editor] [--windows-file-paths] [--handles 0.5] [--sequence-fps 25]

require 'yaml'
require 'date'
require 'fileutils'
require 'buttercut'

def timecode_to_seconds(timecode)
  parts = timecode.split(':')
  hours = parts[0].to_i
  minutes = parts[1].to_i
  seconds = parts[2].to_f
  hours * 3600 + minutes * 60 + seconds
end

def main
  if ARGV.length < 1
    puts "Usage: #{$0} <scenes.yaml|\"glob\"> [editor] [--windows-file-paths] [--handles N]"
    puts "  editor: premiere (default), resolve, or fcpx"
    puts "  --windows-file-paths: convert Linux/WSL paths to Windows format"
    puts "  --handles N: add N seconds of padding to each clip (default: 0)"
    puts "  --sequence-fps N: override sequence frame rate (e.g., 25 for 25fps)"
    puts "\n  Output goes to <source_video_dir>/buttercut/xml/"
    exit 1
  end

  windows_file_paths = ARGV.include?('--windows-file-paths')

  handles = 0.0
  handles_index = ARGV.index('--handles')
  if handles_index && ARGV[handles_index + 1]
    handles = ARGV[handles_index + 1].to_f
  end

  sequence_fps = nil
  fps_index = ARGV.index('--sequence-fps')
  if fps_index && ARGV[fps_index + 1]
    sequence_fps = ARGV[fps_index + 1].to_i
  end

  args = ARGV.reject.with_index do |a, i|
    a == '--windows-file-paths' ||
      a == '--handles' || (handles_index && i == handles_index + 1) ||
      a == '--sequence-fps' || (fps_index && i == fps_index + 1)
  end

  scenes_input = args[0]
  editor_choice = args[1] || 'premiere'

  # Resolve glob or single file
  scene_files = if scenes_input.include?('*')
                  Dir.glob(scenes_input)
                else
                  [scenes_input]
                end

  abort "Error: No scene files found matching: #{scenes_input}" if scene_files.empty?

  editor_symbol = case editor_choice.downcase
  when 'fcpx', 'finalcutpro', 'finalcut', 'fcp' then :fcpx
  when 'premiere', 'premierepro', 'adobepremiere' then :fcp7
  when 'resolve', 'davinci', 'davinciresolve' then :fcp7
  else
    abort "Error: Unknown editor '#{editor_choice}'. Use 'premiere', 'resolve', or 'fcpx'"
  end

  timestamp = Time.now.strftime('%Y%m%d_%H%M')
  total_exported = 0

  scene_files.each do |scene_file|
    unless File.exist?(scene_file)
      puts "Warning: Scene file not found: #{scene_file}"
      next
    end

    scenes = YAML.load_file(scene_file, permitted_classes: [Date, Time, Symbol])
    source_video = scenes['source_video']

    unless source_video
      puts "Warning: No source_video in #{scene_file}, skipping"
      next
    end

    # Output XML to buttercut/xml/ subfolder next to source video
    source_dir = File.dirname(source_video)
    xml_dir = File.join(source_dir, 'buttercut', 'xml')
    FileUtils.mkdir_p(xml_dir)

    basename = File.basename(source_video, '.*')

    scenes['clips'].each_with_index do |clip, idx|
      scene_num = format('%02d', idx + 1)
      start_at = timecode_to_seconds(clip['in_point'])
      out_point = timecode_to_seconds(clip['out_point'])

      # Apply handles (padding)
      start_at = [start_at - handles, 0].max
      out_point += handles

      duration = out_point - start_at
      next if duration <= 0

      buttercut_clips = [{
        path: source_video,
        start_at: start_at.to_f,
        duration: duration.to_f
      }]

      output_file = File.join(xml_dir, "#{basename}_scene_#{scene_num}_#{timestamp}.xml")

      options = { editor: editor_symbol, windows_file_paths: windows_file_paths }
      options[:sequence_frame_rate] = sequence_fps if sequence_fps
      generator = ButterCut.new(buttercut_clips, **options)
      generator.save(output_file)

      puts "  Exported: #{File.basename(output_file)}"
      total_exported += 1
    end
  end

  puts "\nExported #{total_exported} scene(s)"
end

main
