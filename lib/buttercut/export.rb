#!/usr/bin/env ruby
# Export rough cut YAML to editor XML using ButterCut.
#
# Edition shim plus the shared CLI entrypoint. Loads the single-track (core) or
# multi-track (pro) exporter via ButterCut.engine_variant — see
# lib/buttercut/version.rb.
require_relative 'boot'

require 'optparse'
require_relative 'version'
require_relative ButterCut.engine_variant('export')

if __FILE__ == $PROGRAM_NAME
  options = { editor: 'fcpx' }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] <roughcut.yaml> <output.xml>"
    opts.on('-e', '--editor EDITOR', 'fcpx (default), premiere, resolve, or resolve_legacy (temporary FCP7 fallback)') { |v| options[:editor] = v }
    opts.on('-h', '--help', 'Show usage') { puts opts; exit }
  end
  parser.parse!

  if ARGV.length != 2
    warn parser.help
    exit 1
  end

  begin
    Export.perform(roughcut_path: ARGV[0], output_path: ARGV[1], editor: options[:editor])
  rescue ArgumentError, RuntimeError => e
    warn "Error: #{e.message}"
    exit 1
  end
end
