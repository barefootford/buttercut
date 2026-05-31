#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

# Tees process_footage.rb's progress to both the console and a daily file under
# tmp/, so an unattended run (e.g. while the Mac is locked) leaves a reviewable
# record of what ran when. The console gets the plain lines; the file gets each
# line stamped with a wall-clock time — which is exactly what makes job ordering
# and timing legible after the fact ("did sheets run during transcripts?").
#
# ONE file per library per day: tmp/logs/processing/<library>/<YYYY-MM-DD>.log
# (tmp/ is gitignored). Every run APPENDS, so the transcripts and contact-sheets
# steps — and any re-runs that day — land in the same file, separated by a blank
# line. RunLog is a dumb tee: it stays out of *what* is being processed. The
# caller (process_footage.rb / FootageProcessor) logs the orchestration header
# ("Processing transcripts: 30 clip(s).") that names each step; JobRunner logs
# the individual job events. Quacks like an IO enough for both: it answers #puts
# and #sync=.
class RunLog
  ROOT = File.expand_path('../../tmp/logs/processing', __dir__)

  attr_reader :path

  def initialize(library_name, console: $stdout, root: ROOT, now: Time.now)
    dir = File.join(root, sanitize(library_name))
    FileUtils.mkdir_p(dir)
    @path = File.join(dir, "#{now.strftime('%Y-%m-%d')}.log")
    appending = File.size?(@path) # truthy only if the day's file already has content
    @file = File.open(@path, 'a')
    @file.sync = true
    @file.puts if appending # blank line separates this run from the previous one
    @console = console
  end

  def puts(message = '')
    line = message.to_s
    @console.puts(line)
    @file.puts(line.empty? ? '' : "#{Time.now.strftime('%H:%M:%S')}  #{line}")
  end

  # status_server and other callers may flip sync on their stream; forward it.
  def sync=(flag)
    @console.sync = flag if @console.respond_to?(:sync=)
  end

  def close
    @file.close unless @file.closed?
  end

  private

  def sanitize(name) = name.to_s.gsub(%r{[/\\\s]+}, '_')
end
