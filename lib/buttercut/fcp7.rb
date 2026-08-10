# Edition shim. Loads the single-track (core) or multi-track (pro) FCP7/xmeml
# generator (the base Premiere subclasses). See ButterCut.engine_variant in
# lib/buttercut/version.rb.
require_relative 'version'
require_relative ButterCut.engine_variant('fcp7')
