# Edition shim for the DaVinci Resolve generator. See ButterCut.engine_variant
# in lib/buttercut/version.rb.
require_relative 'version'
require_relative ButterCut.engine_variant('resolve')
