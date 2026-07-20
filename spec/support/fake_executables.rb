# frozen_string_literal: true

# Writes a chmod-755 stub script posing as an installed binary and returns its
# path. Used by the PATH-resolution specs (Platform, MediaTools).
module FakeExecutables
  def install(dir, name)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n")
    File.chmod(0o755, path)
    path
  end
end

RSpec.configure { |config| config.include FakeExecutables }
