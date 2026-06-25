# Edition shim. Loads the single-track (core) or multi-track (pro) FCPX
# generator. See ButterCut.engine_variant in lib/buttercut/version.rb.
require_relative 'version'
require_relative ButterCut.engine_variant('fcpx')
