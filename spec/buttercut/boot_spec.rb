# frozen_string_literal: true

require 'open3'

# spec_helper loads lib/buttercut.rb, which pulls in the exporters but not the
# CLI entry points, so the gate's own constants need requiring here.
require_relative '../../lib/buttercut/boot'

# The Ruby-version gate only works if the file carrying it can be parsed by the
# old interpreter that trips the problem. That makes "entry points stay
# 2.6-parseable, and require boot.rb first" a real invariant, easy to break by
# writing a perfectly ordinary endless method in the wrong file. These specs are
# the tripwire.
RSpec.describe 'boot gate' do
  REPO_ROOT = File.expand_path('../..', __dir__)
  SYSTEM_RUBY = '/usr/bin/ruby'

  # Derived from the docs rather than hardcoded: a file is an entry point
  # exactly when we tell people (or agents) to run it with `ruby <path>`. Add a
  # documented invocation and it is covered here automatically.
  def self.documented_entry_points
    sources = Dir[File.join(REPO_ROOT, 'skills', '**', '*.md')] +
              [File.join(REPO_ROOT, 'AGENTS.md')]
    # Explicit encoding: the docs are full of em-dashes, and a shell with no
    # LANG set would otherwise read them as US-ASCII and blow up on scan.
    sources.flat_map { |file| File.read(file, encoding: 'UTF-8').scan(%r{\bruby (lib/buttercut/[a-z_0-9]+\.rb)}) }
           .flatten
           .uniq
           .sort
  end

  ENTRY_POINTS = documented_entry_points

  it 'finds the documented entry points' do
    # Guards the derivation itself: a bad regex would silently make every
    # example below vacuous.
    expect(ENTRY_POINTS).to include('lib/buttercut/library.rb')
    expect(ENTRY_POINTS.size).to be >= 8
  end

  describe 'each documented entry point' do
    ENTRY_POINTS.each do |relative_path|
      context relative_path do
        let(:full_path) { File.join(REPO_ROOT, relative_path) }
        let(:source) { File.read(full_path, encoding: 'UTF-8') }

        it 'exists' do
          expect(File).to exist(full_path)
        end

        it 'requires boot before anything else in the project' do
          first_local_require = source[/^require_relative .*$/]
          expect(first_local_require).to eq("require_relative 'boot'")
        end

        # The actual property we care about: old Ruby can read the file far
        # enough to run the gate. Skipped rather than failed off-macOS so the
        # suite stays portable.
        it 'parses under system Ruby 2.6' do
          skip "#{SYSTEM_RUBY} not present" unless File.executable?(SYSTEM_RUBY)

          _out, err, status = Open3.capture3(SYSTEM_RUBY, '-c', full_path, chdir: REPO_ROOT)
          expect(status).to be_success, "#{relative_path} is not parseable by system Ruby:\n#{err}"
        end
      end
    end
  end

  describe 'boot.rb itself' do
    let(:full_path) { File.join(REPO_ROOT, 'lib/buttercut/boot.rb') }

    # rspec runs under `bundle exec`, which exports RUBYOPT=-rbundler/setup.
    # Handing that to system Ruby makes 2.6 try to load the 3.3 bundler and die
    # before the gate gets a turn. Skills invoke these scripts as plain `ruby
    # <path>` with no bundler in sight, so clearing it is also the honest
    # reproduction of how they actually run.
    def unbundled(extra = {})
      cleared = ENV.keys.grep(/\A(RUBYOPT|RUBYLIB|BUNDLE_|GEM_)/).each_with_object({}) do |key, env|
        env[key] = nil
      end
      cleared.merge(extra)
    end

    it 'parses under system Ruby 2.6' do
      skip "#{SYSTEM_RUBY} not present" unless File.executable?(SYSTEM_RUBY)

      _out, err, status = Open3.capture3(SYSTEM_RUBY, '-c', full_path, chdir: REPO_ROOT)
      expect(status).to be_success, "boot.rb must stay 2.6-parseable:\n#{err}"
    end

    it 'hands a too-old interpreter off to a current one' do
      skip "#{SYSTEM_RUBY} not present" unless File.executable?(SYSTEM_RUBY)

      script = File.join(REPO_ROOT, 'spec', 'fixtures', 'boot_probe.rb')
      out, err, status = Open3.capture3(unbundled, SYSTEM_RUBY, script, 'alpha', 'beta', chdir: REPO_ROOT)

      expect(status).to be_success, "re-exec failed:\n#{err}"
      version, args = out.strip.split(' ', 2)
      expect(Gem::Version.new(version)).to be >= Gem::Version.new(ButterCut::Boot::MINIMUM_RUBY)
      expect(args).to eq('alpha beta')
    end

    it 'does not re-exec a second time' do
      # Belt and braces on the loop guard: with the flag already set, an old
      # interpreter must fail loudly instead of spawning itself forever.
      skip "#{SYSTEM_RUBY} not present" unless File.executable?(SYSTEM_RUBY)

      script = File.join(REPO_ROOT, 'spec', 'fixtures', 'boot_probe.rb')
      env = unbundled(ButterCut::Boot::REEXEC_FLAG => '1')
      _out, err, status = Open3.capture3(env, SYSTEM_RUBY, script, chdir: REPO_ROOT)

      expect(status).not_to be_success
      expect(err).to include('needs Ruby')
      expect(err).to include('not a bad checkout')
    end
  end
end
