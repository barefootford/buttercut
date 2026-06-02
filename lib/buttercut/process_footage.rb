#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'footage_processor'
require_relative 'run_log'

# The two mechanical footage steps, as one dispatcher with two subcommands the
# agent runs back-to-back — transcripts first, then contact-sheets:
#
#   ruby lib/buttercut/process_footage.rb transcripts    <library> [opts]
#   ruby lib/buttercut/process_footage.rb contact-sheets <library> [opts]
#
# There's no "do both" mode on purpose: the agent waits for transcripts to finish
# before starting contact-sheets, so the slow whisperx pass never overlaps the
# fast ffmpeg one and total concurrency stays at the cap (settings.yaml
# `parallel_jobs`, default 2), not double it. Each step runs the clips still
# missing that artifact, ~2 at a time, recording each into library.yaml as it
# lands. Idempotent: safe to re-run; --force rebuilds artifacts that exist.
ACTIONS = {
  'transcripts'    => :transcribe,
  'contact-sheets' => :build_contact_sheets
}.freeze

BANNER = 'Usage: ruby process_footage.rb <transcripts|contact-sheets> <library_name> ' \
         '[--jobs N] [--force] [--clips a.mov,b.mov]'

options = { jobs: nil, force: false, clips: nil }
parser = OptionParser.new do |opts|
  opts.banner = BANNER
  opts.on('--jobs N', Integer, 'Clips to run at once (overrides settings.yaml parallel_jobs; default 2)') { |n| options[:jobs] = n }
  opts.on('--force', 'Rebuild artifacts even if they already exist (for reprocessing)') { options[:force] = true }
  opts.on('--clips a.mov,b.mov', Array, 'Limit work to these clip filenames') { |c| options[:clips] = c }
end
parser.parse!

command = ARGV.shift
action = ACTIONS[command.to_s]
unless action
  warn "Unknown step #{command.inspect}. Expected: #{ACTIONS.keys.join(' | ')}"
  warn parser.banner
  exit 1
end

library = ARGV.shift
if library.to_s.empty?
  warn parser.banner
  exit 1
end

log = RunLog.new(library)
log.puts "Logging to #{log.path}"
begin
  ok = FootageProcessor.new(library, **options, io: log).public_send(action)
  exit(ok ? 0 : 1)
rescue StandardError => e
  warn "#{command}: #{e.message}"
  exit 1
ensure
  log.close
end
