#!/usr/bin/env ruby
# Lightweight daily update check for ButterCut.
# Invoked at the top of entry-point skills. Silent unless an update is available.

require "json"
require "net/http"
require "time"
require "uri"
require "rubygems/version"

REPO_ROOT = File.expand_path("../../..", __FILE__)
MARKER = File.join(REPO_ROOT, ".last_update_check")
GITHUB_API = "https://api.github.com/repos/barefootford/buttercut/releases/latest"
THROTTLE_SECONDS = 24 * 60 * 60
TIMEOUT_SECONDS = 5

last_check = (Time.parse(File.read(MARKER).strip) rescue nil) if File.exist?(MARKER)
exit 0 if last_check && (Time.now - last_check) < THROTTLE_SECONDS

# Write the timestamp first so a hang or failure doesn't make us re-check on every call today.
File.write(MARKER, Time.now.iso8601 + "\n")

begin
  version_file = File.read(File.join(REPO_ROOT, "lib", "buttercut", "version.rb"))
  local = version_file[/VERSION\s*=\s*["']([^"']+)["']/, 1]
  exit 0 unless local

  uri = URI(GITHUB_API)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                       open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
    http.get(uri.request_uri,
             "Accept" => "application/vnd.github+json",
             "User-Agent" => "buttercut-update-check")
  end
  exit 0 unless res.is_a?(Net::HTTPSuccess)

  latest = JSON.parse(res.body)["tag_name"].to_s.sub(/\Av/, "")
  exit 0 if latest.empty?

  if Gem::Version.new(latest) > Gem::Version.new(local)
    puts "ButterCut #{local} → #{latest} available. Run the update-buttercut skill to upgrade."
  end
rescue
  # Network down, JSON parse error, etc. Stay silent — marker is already touched.
end
