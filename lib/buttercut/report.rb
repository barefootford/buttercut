#!/usr/bin/env ruby
# frozen_string_literal: true

# Consent-based reporting. Two things travel from a ButterCut install to the
# developers, and both go through this file: bug reports and feature requests.
# When a ButterCut CLI hits an unexpected exception, `Report.capture!` writes a
# crash dump — a full report draft — under reports/ and prints a banner
# pointing the agent at the report-bug skill. Feature requests start empty,
# from `Report.new_feature_request`. Nothing ever leaves the machine without
# the user's say-so: `send` posts a reviewed report file to the ButterCut
# report endpoint (TubeSalt), honoring the consent file and a local ledger so
# one fingerprint is only sent once. Reports carry technical metadata only —
# never transcript text, never full paths.

require 'digest'
require 'English'
require 'fileutils'
require 'json'
require 'net/http'
require 'securerandom'
require 'shellwords'
require 'time'
require 'uri'

require_relative 'version'
require_relative 'media_tools'

class ButterCut
  # Raise for expected, user-fixable failures (bad input, missing file):
  # they print cleanly and never produce a crash dump.
  class UserError < StandardError; end

  class Report
    SCHEMA_VERSION = 1
    KINDS = %w[bug feature].freeze
    REPO_ROOT = File.expand_path('../..', __dir__)
    REPORTS_DIR = File.join(REPO_ROOT, 'reports')
    LEDGER_FILE = File.join(REPORTS_DIR, '.sent_fingerprints.json')
    CONSENT_FILE = File.join(REPO_ROOT, '.buttercut_reporting')
    LICENSE_FILE = File.join(REPO_ROOT, '.buttercut_pro_license')
    CONSENT_STATES = %w[ask always never].freeze
    DEFAULT_ENDPOINT = 'https://tubesalt.com/api/v1/buttercut_reports'
    MAX_REPORT_BYTES = 48 * 1024 # the server rejects bodies over 64 KB; leave headroom
    BACKTRACE_LIMIT = 40
    TITLE_LIMIT = 255 # the server truncates past this — clip here so the user reviews what's stored

    # Expected error classes never dump — they're user- or agent-fixable and
    # their message is the whole story. Matched by ancestor name so this file
    # needs no require on the files that define them (library.rb requires this
    # file, not the other way around).
    EXPECTED_ERRORS = %w[ArgumentError ButterCut::UserError
                         MediaTools::MissingBinary Library::UpdateCheckNeeded].freeze

    class << self
      # Called from CLI rescue blocks after their usual `warn`. Writes a dump
      # and prints the banner for unexpected errors; a no-op for expected ones
      # and in developer checkouts (raises are part of working on the code).
      # Must never mask the original failure, so it swallows its own errors.
      def capture!(error, action:)
        return if expected?(error)
        return if developer? && !ENV['BUTTERCUT_FORCE_ERROR_CAPTURE']

        path = write_dump(error, action: action)
        warn banner(path)
        path
      rescue StandardError
        nil
      end

      def expected?(error)
        error.class.ancestors.filter_map(&:name).intersect?(EXPECTED_ERRORS)
      end

      def developer? = File.exist?(File.join(REPO_ROOT, '.buttercut_mode'))

      # ask (default, absent file) — ask the user before every send.
      # always — send reviewed reports without re-asking. never — never send.
      def consent
        return 'ask' unless File.exist?(CONSENT_FILE)

        value = File.read(CONSENT_FILE).strip.downcase
        CONSENT_STATES.include?(value) ? value : 'ask'
      end

      def consent=(value)
        raise UserError, "consent must be one of: #{CONSENT_STATES.join(', ')}" unless CONSENT_STATES.include?(value)

        File.write(CONSENT_FILE, "#{value}\n")
      end

      def write_dump(error, action:)
        write_report(draft(
                       kind: 'bug',
                       source: 'cli',
                       fingerprint: fingerprint(error, action: action),
                       title: clip("#{error.class.name} during #{action}"),
                       error: {
                         'class' => error.class.name,
                         'message' => scrub(error.message.to_s),
                         'action' => action,
                         'argv' => ARGV.map { |arg| scrub(arg) },
                         'backtrace' => (error.backtrace || []).first(BACKTRACE_LIMIT).map { |line| scrub(relativize(line)) }
                       }
                     ))
      end

      # A bug the agent saw with no Ruby crash dump behind it (ffmpeg exits,
      # malformed XML, a skill dead end). The summary seeds the fingerprint, so
      # keep it short and stable — a title, not a paragraph.
      def new_bug_report(action, summary)
        summary = require_text(summary, '--summary')
        write_report(draft(
                       kind: 'bug',
                       source: 'agent',
                       fingerprint: hash_key('agent', action, summary.downcase),
                       title: clip(summary),
                       error: { 'class' => nil, 'message' => scrub(summary), 'action' => action,
                                'argv' => nil, 'backtrace' => nil }
                     ))
      end

      # A feature the user asked for. No error and no CLI action — the title is
      # the whole identity, so it seeds the fingerprint and two people asking
      # for the same thing in the same words land on one row server-side.
      def new_feature_request(title)
        title = require_text(title, '--title')
        write_report(draft(
                       kind: 'feature',
                       source: 'user',
                       fingerprint: hash_key('feature', title.downcase),
                       title: clip(title),
                       error: nil
                     ))
      end

      # Technical metadata only — basename, container, codecs, geometry. Never
      # transcript text, never the full path. A probe failure is itself signal
      # (the file may be exactly what broke), so it's returned, not raised.
      def probe(path)
        output = `#{Shellwords.escape(MediaTools.ffprobe)} -v error -show_format -show_streams -of json #{Shellwords.escape(path)} 2>&1`
        raise output.strip.empty? ? 'ffprobe produced no output' : output.strip unless $CHILD_STATUS.success?

        data = JSON.parse(output)
        video = (data['streams'] || []).find { |s| s['codec_type'] == 'video' } || {}
        audio = (data['streams'] || []).find { |s| s['codec_type'] == 'audio' } || {}
        {
          'file' => File.basename(path),
          'container' => data.dig('format', 'format_name'),
          'duration' => data.dig('format', 'duration'),
          'size_bytes' => data.dig('format', 'size')&.to_i,
          'video' => video.slice('codec_name', 'width', 'height', 'pix_fmt', 'r_frame_rate', 'avg_frame_rate'),
          'audio' => audio.slice('codec_name', 'sample_rate', 'channels')
        }
      rescue StandardError => e
        { 'file' => File.basename(path), 'probe_error' => scrub(e.message) }
      end

      # Consent- and ledger-gated POST of a reviewed report file. Returns an
      # outcome hash instead of raising on network trouble — a failed report
      # must never fail the user's actual task, and the file stays on disk.
      def send_report(path, user_approved: false)
        raise UserError, "report file not found: #{path}" unless File.exist?(path)

        report = JSON.parse(File.read(path))
        %w[report_uuid fingerprint title].each do |key|
          raise UserError, "report is missing #{key}" if report[key].to_s.empty?
        end
        noun = noun_for(report)

        if (sent = ledger[report['fingerprint']])
          return outcome('already_reported', "#{noun} was already sent on #{sent['sent_at']} — no need to send it again")
        end
        return outcome('skipped', 'reporting is set to never — nothing was sent') if consent == 'never'
        if consent == 'ask' && !user_approved
          return outcome('needs_approval', "show the user what #{noun} contains, ask permission, then re-run send with --user-approved")
        end

        body = JSON.generate(report)
        raise UserError, "report is #{body.bytesize} bytes — trim narrative/media below #{MAX_REPORT_BYTES}" if body.bytesize > MAX_REPORT_BYTES

        response = post(body)
        return outcome('failed', "server responded #{response.code} — the report file is kept locally; try again later") unless response.code.start_with?('2')

        record_sent(report['fingerprint'], report['report_uuid'])
        server = begin
          JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          {}
        end
        outcome('sent', 'report delivered — thank the user', server: server)
      rescue UserError
        raise
      rescue StandardError => e
        outcome('failed', "could not reach the report endpoint (#{e.class}) — the report file is kept locally")
      end

      def list
        return [] unless File.directory?(REPORTS_DIR)

        sent = ledger
        Dir[File.join(REPORTS_DIR, '*.json')].sort.map do |path|
          report = begin
            JSON.parse(File.read(path))
          rescue JSON::ParserError
            {}
          end
          fingerprint = report['fingerprint']
          { 'file' => relativize(path), 'kind' => report['kind'], 'title' => report['title'],
            'fingerprint' => fingerprint, 'reported' => sent.key?(fingerprint.to_s) }
        end
      end

      # Fingerprint = error class + topmost in-repo frame (line number
      # stripped, so unrelated edits to the file don't split the group) +
      # CLI action. Version stays out on purpose: the same bug across
      # releases must group as one.
      def fingerprint(error, action:)
        frame = app_frame(error) || (error.backtrace || []).first.to_s
        hash_key(error.class.name, normalize_frame(frame), action)
      end

      private

      def draft(kind:, source:, fingerprint:, title:, error:)
        {
          'schema_version' => SCHEMA_VERSION,
          'kind' => kind,
          'report_uuid' => SecureRandom.uuid,
          'fingerprint' => fingerprint,
          'title' => title,
          'source' => source,
          'created_at' => Time.now.utc.iso8601,
          'buttercut' => { 'version' => ButterCut::VERSION, 'edition' => ButterCut::EDITION.to_s },
          'environment' => environment,
          'error' => error,
          'media' => [],
          'narrative' => nil,
          'workaround' => nil,
          'agent' => nil,
          'contact_email' => nil
        }
      end

      def write_report(report)
        FileUtils.mkdir_p(REPORTS_DIR)
        stamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
        path = File.join(REPORTS_DIR, "#{stamp}-#{report['kind']}-#{report['fingerprint']}.json")
        File.write(path, JSON.pretty_generate(report))
        path
      end

      def hash_key(*parts) = Digest::SHA256.hexdigest(parts.join('|'))[0, 12]

      def require_text(value, flag)
        text = value.to_s.strip
        raise UserError, "a short #{flag} is required" if text.empty?

        text
      end

      def clip(text) = text.to_s.strip[0, TITLE_LIMIT]

      def noun_for(report) = report['kind'] == 'feature' ? 'this feature request' : 'this bug report'

      def banner(path)
        <<~BANNER
          BUTTERCUT ERROR CAPTURED: #{relativize(path)}
          If this failure came from your own input (a wrong path, a malformed cut
          file), fix the input and move on — no report needed. If ButterCut itself
          misbehaved: do not edit ButterCut's code (lib/, skills/, scripts/) to work
          around it. Use the report-bug skill to tell the developers what happened
          (only ever sent with the user's permission), and put any temporary
          workaround in a user- skill (skills/user-*/), never in lib/.
        BANNER
      end

      def environment
        { 'ruby' => RUBY_VERSION, 'macos' => macos_version, 'ffmpeg' => ffmpeg_version }
      end

      def macos_version
        return nil unless RUBY_PLATFORM.include?('darwin')

        `sw_vers -productVersion 2>/dev/null`.strip
      rescue StandardError
        nil
      end

      def ffmpeg_version
        `#{Shellwords.escape(MediaTools.ffmpeg)} -version 2>/dev/null`.lines.first.to_s[/ffmpeg version (\S+)/, 1]
      rescue StandardError
        nil
      end

      def app_frame(error)
        (error.backtrace || []).find { |line| line.start_with?(REPO_ROOT) }
      end

      def normalize_frame(frame) = relativize(frame).sub(/:\d+:/, ':')

      def relativize(path) = path.sub("#{REPO_ROOT}/", '')

      def scrub(text)
        home = begin
          Dir.home
        rescue StandardError
          nil
        end
        home ? text.gsub(home, '~') : text
      end

      def ledger
        return {} unless File.exist?(LEDGER_FILE)

        JSON.parse(File.read(LEDGER_FILE))
      rescue JSON::ParserError
        {}
      end

      def record_sent(fingerprint, report_uuid)
        entries = ledger.merge(fingerprint => { 'sent_at' => Time.now.utc.iso8601, 'report_uuid' => report_uuid })
        FileUtils.mkdir_p(REPORTS_DIR)
        File.write(LEDGER_FILE, JSON.pretty_generate(entries))
      end

      def outcome(status, note, server: nil)
        { 'outcome' => status, 'note' => note, 'server' => server }.compact
      end

      # Pro installs carry a gitignored key=value license file; attaching its
      # headers ties the report to a customer. Absent on core — that's normal.
      def license_headers
        return {} unless File.exist?(LICENSE_FILE)

        pairs = File.readlines(LICENSE_FILE).filter_map do |line|
          key, value = line.split('=', 2)
          [key.strip, value.strip] if value
        end.to_h
        { 'X-Buttercut-Email' => pairs['email'], 'X-Buttercut-License-Key' => pairs['license_key'] }.compact
      end

      def post(body)
        uri = URI(ENV.fetch('BUTTERCUT_REPORT_ENDPOINT', DEFAULT_ENDPOINT))
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 3
        http.read_timeout = 5
        request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' }.merge(license_headers))
        request.body = body
        http.request(request)
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  USAGE = <<~USAGE
    Usage: ruby lib/buttercut/report.rb <command>

    Commands:
      consent [ask|always|never]        — show or set the reporting consent
      list                              — drafted reports under reports/ and whether each was sent
      bug <action> --summary "<title>"  — draft a bug report for a failure with no crash dump (agent-observed)
      feature --title "<title>"         — draft a feature request the user asked for
      probe <media-file>                — scrubbed technical metadata for a media file (goes in a report's "media")
      send <report.json> [--user-approved]
                                        — send a reviewed report to the ButterCut report endpoint
  USAGE

  def flag_value(args, flag)
    index = args.index(flag)
    index && args[index + 1]
  end

  command, *rest = ARGV

  begin
    case command
    when 'consent'
      ButterCut::Report.consent = rest.first if rest.first
      puts ButterCut::Report.consent
    when 'list'
      puts JSON.pretty_generate(ButterCut::Report.list)
    when 'bug'
      action = rest.shift
      raise ButterCut::UserError, 'bug requires <action>' if action.to_s.empty? || action.start_with?('--')

      puts ButterCut::Report.new_bug_report(action, flag_value(rest, '--summary'))
    when 'feature'
      puts ButterCut::Report.new_feature_request(flag_value(rest, '--title'))
    when 'probe'
      raise ButterCut::UserError, 'probe requires <media-file>' if rest.first.to_s.empty?

      puts JSON.pretty_generate(ButterCut::Report.probe(rest.first))
    when 'send'
      path = rest.reject { |arg| arg.start_with?('--') }.first
      raise ButterCut::UserError, 'send requires <report.json>' if path.to_s.empty?

      puts JSON.pretty_generate(ButterCut::Report.send_report(path, user_approved: rest.include?('--user-approved')))
    else
      warn USAGE
      exit 1
    end
  rescue ButterCut::UserError, ArgumentError => e
    warn "report: #{e.message}"
    exit 1
  end
end
