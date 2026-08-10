#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'net/http'
require 'optparse'
require 'securerandom'
require 'uri'

require_relative 'distribution'
require_relative 'library'
require_relative 'settings'
require_relative 'version'

# Sends bug reports and feature requests to TubeSalt, gated by the consent
# recorded in libraries/settings.yaml. Nothing here prompts, and nothing here
# scrubs: the agent owns both, because it's the one holding the failure.
# See skills/report-bug/SKILL.md.
class Report
  SCHEMA_VERSION = 1
  KINDS = %w[bug feature].freeze
  FINGERPRINT_LENGTH = 12 # the server accepts 8–64 hex chars
  HTTP_TIMEOUT = 5 # seconds; a report is never worth stalling the user over

  def initialize(kind:, title: nil, action: nil, error_class: nil, message: nil,
                 frame: nil, narrative: nil, settings: Settings.load)
    @kind = kind.to_s
    @title = title
    @action = action
    @error_class = error_class
    @message = message
    @frame = frame
    @narrative = narrative
    @settings = settings
    validate!
  end

  # Why this report may not be sent, or nil when it may be. Feature requests
  # skip the error_reporting gate: they're user-initiated and user-approved
  # every time, so someone who turned error reports off can still send one.
  def refusal
    return "this is a developer checkout (.buttercut_mode) — reports are for real installs" if Library.developer?
    return nil if @kind == 'feature'

    case @settings.error_reporting
    when nil then "ButterCut hasn't asked this user about error reporting yet"
    when 'never' then 'this user chose never to send reports'
    end
  end

  # The server's grouping key. Excludes the message on purpose: two crashes that
  # differ only in which file they name are one bug, and should ping once.
  def fingerprint
    seed = @kind == 'feature' ? "feature|#{@title}" : "#{@error_class}|#{@action}|#{@frame}"
    Digest::SHA256.hexdigest(seed)[0, FINGERPRINT_LENGTH]
  end

  # Memoized so the uuid printed back to the agent is the one that went over the wire.
  def payload
    @payload ||= {
      'schema_version' => SCHEMA_VERSION,
      'report_uuid' => SecureRandom.uuid,
      'fingerprint' => fingerprint,
      'kind' => @kind,
      'source' => @kind == 'feature' ? 'user' : 'agent',
      'title' => @title,
      'buttercut' => { 'version' => ButterCut::VERSION, 'edition' => ButterCut::EDITION.to_s },
      'error' => error_section,
      'narrative' => @narrative,
      'contact_email' => @settings.error_report_email
    }
  end

  # [ok, message]. Never raises: a report that doesn't arrive is a non-event for
  # a user whose export already failed.
  def deliver
    reason = refusal
    return [false, "not sent — #{reason}"] if reason

    response = post
    if response.is_a?(Net::HTTPSuccess)
      [true, "sent #{@kind} report #{payload['report_uuid']} (#{response.code})"]
    else
      [false, "not sent — TubeSalt answered #{response.code}"]
    end
  rescue StandardError => e
    [false, "not sent — #{e.class}: #{e.message}"]
  end

  private

  def validate!
    raise ArgumentError, "kind expects #{KINDS.join('/')}, got: #{@kind}" unless KINDS.include?(@kind)

    if @kind == 'feature'
      raise ArgumentError, 'a feature request needs --title' if blank?(@title)
    elsif blank?(@error_class) || blank?(@action)
      raise ArgumentError, 'a bug report needs --class and --action'
    end
  end

  def blank?(value) = value.to_s.strip.empty?

  def error_section
    return nil if @kind == 'feature'

    { 'class' => @error_class, 'message' => @message, 'action' => @action,
      'backtrace' => [@frame].compact }
  end

  def post
    uri = URI(ButterCut::REPORT_ENDPOINT)
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = JSON.generate(payload)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                                            open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
      http.request(request)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  USAGE = <<~TEXT
    Usage:
      report.rb consent                                    print the current choice
      report.rb send --kind bug --action STEP --class CLASS [options]
      report.rb send --kind feature --title TITLE [options]

    Consent lives in libraries/settings.yaml (error_reporting / error_report_email
    — the commented block in templates/settings_template.yaml documents them).
    Strings you pass are sent as-is — scrub anything naming the user's footage first.

    Options for send:
      --message TEXT      the error message
      --frame FILE:LINE   the top ButterCut backtrace frame
      --narrative TEXT    what you observed, in a sentence or two
      --title TEXT        short summary (required for a feature request)
      --dry-run           print the JSON that would be sent; send nothing
  TEXT

  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = USAGE
    opts.on('--kind KIND') { |v| options[:kind] = v }
    opts.on('--title TEXT') { |v| options[:title] = v }
    opts.on('--action STEP') { |v| options[:action] = v }
    opts.on('--class CLASS') { |v| options[:error_class] = v }
    opts.on('--message TEXT') { |v| options[:message] = v }
    opts.on('--frame FRAME') { |v| options[:frame] = v }
    opts.on('--narrative TEXT') { |v| options[:narrative] = v }
    opts.on('--dry-run') { options[:dry_run] = true }
    opts.on('-h', '--help') { puts opts; exit }
  end
  parser.parse!

  begin
    case ARGV.shift
    when 'consent'
      settings = Settings.load
      puts "error_reporting=#{settings.error_reporting || 'unset'} email=#{settings.error_report_email}"
    when 'send'
      report = Report.new(
        kind: options.fetch(:kind, 'bug'), title: options[:title], action: options[:action],
        error_class: options[:error_class], message: options[:message], frame: options[:frame],
        narrative: options[:narrative]
      )

      # Prints even when consent would refuse — showing what would go is how the
      # "ask" and setup questions get answered.
      if options[:dry_run]
        puts JSON.pretty_generate(report.payload)
        reason = report.refusal
        warn "(would not actually send — #{reason})" if reason
      else
        ok, message = report.deliver
        puts message
        exit 1 unless ok
      end
    else
      warn USAGE
      exit 1
    end
  rescue ArgumentError => e
    warn "report: #{e.message}"
    exit 1
  end
end
