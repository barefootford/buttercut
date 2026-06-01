#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'set'
require 'webrick'
require_relative 'library'

# Read-only "follow along" web view of one library's processing progress. No
# inputs — just a table of clips and whether each artifact (transcript, contact
# sheet, summary) exists yet, so a non-technical user can watch while
# `process_footage.rb` runs. The page auto-refreshes with a <meta refresh> tag; every
# request re-reads library.yaml through the Library class, so it's always live.
#
# The library name is optional. The agent usually passes it explicitly (it
# knows from the conversation which library is being processed). When it's
# omitted — e.g. the committed .claude/launch.json, which can't bake in a
# per-user library name — the server follows the most-recently-touched library,
# which during processing is the one actively being written to. It only READS;
# Library's atomic temp+rename writes keep each read whole even while the
# JobRunner is recording progress.
#
#   ruby lib/buttercut/status_server.rb [library-name] [port]
class StatusServer
  DEFAULT_PORT = 4174
  REFRESH_SECONDS = 5
  # One label per processing step, in pipeline order. Drives both the progress
  # bar segments and the table column headers, so the two always match.
  FIELD_LABELS = {
    'transcript'    => 'Audio',
    'contact_sheet' => 'Video',
    'summary'       => 'A/V Summaries'
  }.freeze

  ACTIVE_ROOT = File.expand_path('../../tmp/active', __dir__)

  def initialize(library, port: DEFAULT_PORT, io: $stdout)
    @library = library
    @port = port
    @io = io
  end

  def start
    @io.sync = true if @io.respond_to?(:sync=) # flush the URL promptly when stdout is piped (e.g. the preview app)
    server = build_server
    server.mount_proc('/') do |_req, res|
      res.content_type = 'text/html; charset=utf-8'
      res.body = render
    end
    trap('INT') { server.shutdown }
    @io.puts "Live status for '#{@library.name}' → http://127.0.0.1:#{@port}  (Ctrl-C to stop)"
    server.start
  end

  def build_server
    WEBrick::HTTPServer.new(
      BindAddress: '127.0.0.1',
      Port: @port,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )
  rescue Errno::EADDRINUSE
    abort "Port #{@port} is already in use — the status server may already be running at " \
          "http://127.0.0.1:#{@port}.\nStop that one, or start this on another port: " \
          "ruby lib/buttercut/status_server.rb #{@library.name} <port>"
  end

  # Exposed so the page can be rendered/tested without binding a socket.
  def render
    rows = @library.clip_statuses
    active = active_clips
    total = rows.size
    done = rows.count { |row| FIELD_LABELS.keys.all? { |field| row[field] } }
    steps = step_progress(rows, total)

    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="#{REFRESH_SECONDS}">
        <title>ButterCut — #{esc(@library.name)}</title>
        <style>
          body { font: 15px -apple-system, system-ui, sans-serif; margin: 2rem auto; max-width: 760px; color: #1d1d1f; padding: 0 1rem; }
          h1 { font-size: 1.1rem; margin: 0 0 .25rem; }
          .sub { color: #6e6e73; margin: 0 0 1rem; }
          .steps { display: flex; gap: .75rem; margin: 0 0 1.5rem; }
          .step { flex: 1; }
          .step-head { display: flex; justify-content: space-between; align-items: baseline; margin: 0 0 .35rem; font-size: .7rem; color: #6e6e73; text-transform: uppercase; letter-spacing: .04em; }
          .step-head .count { letter-spacing: 0; font-variant-numeric: tabular-nums; }
          .bar { height: 8px; background: #ececef; border-radius: 4px; overflow: hidden; }
          .bar > i { display: block; height: 100%; background: #34c759; transition: width .3s; }
          table { border-collapse: collapse; width: 100%; }
          th, td { text-align: left; padding: .4rem .6rem; border-bottom: 1px solid #f0f0f0; }
          th { color: #6e6e73; font-weight: 600; font-size: .75rem; text-transform: uppercase; letter-spacing: .04em; }
          td.f { text-align: center; width: 120px; }
          .yes { color: #34c759; font-weight: 700; }
          .no { color: #c7c7cc; }
          .name { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .85rem; }
          .spin { display: inline-block; width: 13px; height: 13px; border: 2px solid #d1d1d6; border-top-color: #007aff; border-radius: 50%; animation: spin .8s linear infinite; vertical-align: middle; }
          @keyframes spin { to { transform: rotate(360deg); } }
          .active { margin: 0 0 1.5rem; padding: 0; list-style: none; }
          .active li { display: flex; align-items: center; gap: .5rem; padding: .25rem 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .85rem; color: #1d1d1f; }
          .active .field { color: #6e6e73; font-size: .75rem; }
        </style>
      </head>
      <body>
        <h1>#{esc(@library.name)}</h1>
        <p class="sub">#{done} / #{total} clips analyzed</p>
        <div class="steps">#{steps.map { |step| step_html(step) }.join}</div>
    #{active_list_html(active)}
        <table>
          <thead><tr><th>Clip</th>#{FIELD_LABELS.values.map { |label| %(<th class="f">#{esc(label)}</th>) }.join}</tr></thead>
          <tbody>
      #{rows.map { |row| row_html(row, active) }.join("\n")}
          </tbody>
        </table>
      </body>
      </html>
    HTML
  end

  private

  # One entry per processing step, each with its own done/total/percent so the
  # bar can show progress relative to that step rather than overall completion.
  def step_progress(rows, total)
    FIELD_LABELS.map do |field, label|
      done = rows.count { |row| row[field] }
      percent = total.zero? ? 0 : (100.0 * done / total).round
      { label: label, done: done, total: total, percent: percent }
    end
  end

  def step_html(step)
    <<~HTML
      <div class="step">
        <div class="step-head"><span>#{esc(step[:label])}</span><span class="count">#{step[:done]}/#{step[:total]}</span></div>
        <div class="bar"><i style="width: #{step[:percent]}%"></i></div>
      </div>
    HTML
  end

  def row_html(row, active)
    cells = FIELD_LABELS.keys.map do |field|
      if row[field]
        %(<td class="f"><span class="yes">✓</span></td>)
      elsif active.include?([field, row['filename']])
        %(<td class="f"><span class="spin"></span></td>)
      else
        %(<td class="f"><span class="no">—</span></td>)
      end
    end.join
    %(<tr><td class="name">#{esc(row['filename'])}</td>#{cells}</tr>)
  end

  def active_list_html(active)
    return '' if active.empty?

    items = active.map do |field, clip|
      label = FIELD_LABELS[field] || field
      %(<li><span class="spin"></span> #{esc(clip)} <span class="field">#{esc(label)}</span></li>)
    end.join("\n    ")
    %(<ul class="active">\n    #{items}\n    </ul>)
  end

  def active_clips
    dir = File.join(ACTIVE_ROOT, @library.name)
    return Set.new unless Dir.exist?(dir)

    Dir.glob(File.join(dir, '*', '*')).each_with_object(Set.new) do |path, set|
      field = File.basename(File.dirname(path))
      clip  = File.basename(path)
      set.add([field, clip])
    end
  end

  def esc(text) = CGI.escapeHTML(text.to_s)
end

if __FILE__ == $PROGRAM_NAME
  name, port_arg = ARGV
  name = name.to_s.strip

  if name.empty?
    # No name given — the case for the committed .claude/launch.json, which
    # can't bake in a per-user library name. Follow the most-recently-touched
    # library; during processing that's the one actively being written to.
    name = Library.recent(limit: 1).first
    if name.nil?
      warn 'No libraries found yet. Process one first, or pass a name: ruby status_server.rb <library-name> [port]'
      exit 1
    end
  elsif !Library.exists?(name)
    warn "Library not found: #{name}"
    exit 1
  end

  port = port_arg.to_s.strip.empty? ? StatusServer::DEFAULT_PORT : Integer(port_arg, exception: false)
  unless port&.positive?
    warn "Invalid port: #{port_arg.inspect}"
    exit 1
  end

  StatusServer.new(Library.find(name), port: port).start
end
