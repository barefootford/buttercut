# Edition shim. Loads the single-track (core) or multicam-flattening (pro)
# Premiere generator. See ButterCut.engine_variant in lib/buttercut/version.rb.
require_relative 'version'
require_relative ButterCut.engine_variant('premiere')
