#!/usr/bin/env ruby
# Export rough cut YAML to Final Cut Pro XML using ButterCut

require 'yaml'

def timecode_to_seconds(timecode)
  # Convert HH:MM:SS or HH:MM:SS.s to seconds (supports decimal seconds)
  parts = timecode.split(':')
  hours = parts[0].to_i
  minutes = parts[1].to_i
  seconds = parts[2].to_f  # to_f handles both "03" and "03.5"
  hours * 3600 + minutes * 60 + seconds
end

def main
  if ARGV.length < 2 || ARGV.length > 3
    puts "Usage: #{$0} <roughcut.yaml> <output.xml> [editor]"
    puts "  editor: fcpx (default), premiere, or resolve"
    exit 1
  end

  roughcut_path = ARGV[0]
  output_path = ARGV[1]
  editor_choice = ARGV[2] || 'fcpx'

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

    buttercut_clips << {
      path: full_path,
      start_at: start_at.to_f,
      duration: duration.to_f
    }
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

  puts "Converting #{buttercut_clips.length} clips to #{editor_name} XML..."

  # Generate Ruby code to call ButterCut
  ruby_code = <<~RUBY
    require 'buttercut'

    clips = #{buttercut_clips.inspect}

    generator = ButterCut.new(clips, editor: :#{editor_symbol})
    generator.save('#{output_path}')

    puts "Successfully exported to #{output_path}"
  RUBY

  # Execute the Ruby code with lib path
  system("ruby", "-I", File.join(__dir__, "../../../lib"), "-e", ruby_code)

  if $?.success?
    puts "\n✓ Rough cut exported to: #{output_path}"
  else
    puts "\n✗ Error exporting rough cut"
    exit 1
  end
end

main
