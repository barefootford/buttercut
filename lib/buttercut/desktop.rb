#!/usr/bin/env ruby
# frozen_string_literal: true

# The user's Desktop: where it is, and putting a file on it.
#
#   ruby lib/buttercut/desktop.rb            # print the Desktop's path
#   ruby lib/buttercut/desktop.rb "<path>"   # copy a file there, print where it landed
#
# The Desktop isn't always ~/Desktop — see Platform.desktop_dir — so both
# forms ask rather than assume, and the copy fails loudly instead of landing
# somewhere the user will never look.

require 'fileutils'
require_relative 'platform'

module Desktop
  module_function

  def dir = Platform.desktop_dir

  # Copy `path` to the Desktop and return the destination.
  def copy(path)
    source = File.expand_path(path)
    raise ArgumentError, "No such file: #{source}" unless File.exist?(source)

    # Deliberately not creating it: a Desktop that isn't there is a sign we've
    # got the wrong location, and inventing the folder would hide that.
    raise ArgumentError, "Desktop folder not found at #{dir}" unless Dir.exist?(dir)

    destination = File.join(dir, File.basename(source))
    FileUtils.cp(source, destination)
    destination
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    target = ARGV.first
    puts target.to_s.empty? ? Desktop.dir : "copied to: #{Desktop.copy(target)}"
  rescue ArgumentError, SystemCallError => e
    warn "desktop: #{e.message}"
    exit 1
  end
end
