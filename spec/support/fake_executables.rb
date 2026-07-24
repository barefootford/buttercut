# frozen_string_literal: true

require_relative '../../lib/buttercut/platform'

# Writes a chmod-755 stub script posing as an installed binary and returns its
# path. Used by the PATH-resolution specs (Platform, MediaTools).
#
# A bare name picks up .exe on Windows, because that's the only way the file
# counts as executable there — File.executable? goes by extension, not a mode
# bit. Pass an explicit extension when the extension is what's under test.
module FakeExecutables
  def install(dir, name)
    name = "#{name}.exe" if Platform.windows? && File.extname(name).empty?
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n")
    File.chmod(0o755, path)
    path
  end
end

RSpec.configure { |config| config.include FakeExecutables }
