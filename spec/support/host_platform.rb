# frozen_string_literal: true

require 'erb'

# The suite runs on macOS, Linux, and Windows CI. A few expectations depend on
# the real host filesystem rather than on Platform's (stubbable) host_os:
# absolute paths grow a drive letter on Windows, bare-name files aren't
# executable there, and the exporters write Premiere's drive-letter URL form.
module HostPlatform
  # The real host, independent of any Platform.host_os stub in the example.
  def windows_host? = Gem.win_platform?

  # The file:// URL the exporters write for `path` on this host. POSIX keeps
  # the literal file:///tmp/x shape; on Windows the same path expands onto the
  # current drive and takes the file://localhost/D%3a/tmp/x form. The URL
  # algorithm itself is pinned by literal expectations in fcpx_spec's
  # #path_to_file_url examples — this helper only follows the host.
  def file_url_for(path)
    abs = File.expand_path(path)
    encode = ->(p) { p.split('/', -1).map { |s| ERB::Util.url_encode(s) }.join('/') }
    if (drive = abs[%r{\A([A-Za-z]):/}, 1])
      "file://localhost/#{drive}%3a/#{encode.call(abs[3..])}"
    else
      "file://#{encode.call(abs)}"
    end
  end
end

RSpec.configure { |config| config.include HostPlatform }
