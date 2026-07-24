#!/usr/bin/env ruby
# frozen_string_literal: true

# Put an exported file in front of the user, however this machine does that.
#
#   ruby lib/buttercut/reveal.rb <path> ["Adobe Premiere Pro"]
#
# With an application name on macOS, the file opens there. Otherwise it gets
# revealed in the file manager, selected — which is the only sane move on
# Windows, where Premiere and Resolve *import* these XMLs rather than open
# them, and the .xml association would hand it to a browser instead.
#
# Prints one line saying which of those happened, so the caller can tell the
# user something true without having to know the platform rules itself:
#
#   opened in Final Cut Pro: /Users/andrew/…/cut.fcpxml
#   revealed in the file manager: C:\Users\andrew\…\cut.xml
#   exported to: /home/andrew/…/cut.xml        (nothing to open or reveal with)

require_relative 'platform'

module Reveal
  module_function

  # Where macOS keeps applications. Empty everywhere else, which is what makes
  # the name-matching fallback below a no-op off macOS rather than a branch.
  APPLICATION_DIRS = ['/Applications', File.join(Dir.home, 'Applications')].freeze

  def perform(path, app = nil)
    path = File.expand_path(path)
    raise ArgumentError, "No such file: #{path}" unless File.exist?(path)

    opened_with_app(path, app) || revealed(path) || printed(path)
  end

  # Returns the message on success, nil if there's no app to open with here.
  def opened_with_app(path, app)
    return nil if app.to_s.empty?

    name = [app, installed_app_matching(app)].compact.uniq.find do |candidate|
      argv = Platform.open_with_app_argv(candidate, path)
      argv && system(*argv, err: File::NULL)
    end
    return nil unless name

    "opened in #{name}: #{path}"
  end

  # `open -a` matches the application's name exactly, so a version-suffixed
  # install ("Adobe Premiere Pro 2026") misses even though the app is sitting
  # right there. Find what's actually installed and try that before giving up.
  def installed_app_matching(app)
    installed_app_names.find { |name| name.downcase.start_with?(app.downcase) }
  end

  # Every application name this machine offers. One level down as well as the
  # top level, because Adobe (among others) puts the bundle inside a folder of
  # its own — /Applications/Adobe Premiere Pro 2026/Adobe Premiere Pro 2026.app.
  def installed_app_names
    APPLICATION_DIRS.flat_map do |dir|
      children(dir).flat_map do |entry|
        next [app_name(entry)] if entry.end_with?('.app')

        children(File.join(dir, entry)).filter_map { |child| app_name(child) if child.end_with?('.app') }
      end
    end
  end

  def app_name(entry) = File.basename(entry, '.app')

  # Missing, unreadable, or not a directory at all — all "nothing here".
  def children(dir)
    Dir.children(dir)
  rescue SystemCallError
    []
  end

  def revealed(path)
    argv = Platform.reveal_argv(path)
    return nil unless argv

    # Explorer exits non-zero even when it worked, so the status says nothing
    # useful here and we don't check it.
    system(*argv, err: File::NULL)
    "revealed in the file manager: #{path}"
  end

  def printed(path) = "exported to: #{path}"
end

if __FILE__ == $PROGRAM_NAME
  target, app = ARGV
  if target.to_s.empty?
    warn 'Usage: ruby reveal.rb <path> [<application name>]'
    exit 1
  end

  begin
    puts Reveal.perform(target, app)
  rescue ArgumentError => e
    warn "reveal: #{e.message}"
    exit 1
  end
end
