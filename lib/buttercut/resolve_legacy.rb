# Edition shim for the temporary DaVinci Resolve FCP7-fallback generator. See
# ButterCut.engine_variant in lib/buttercut/version.rb.
require_relative 'version'
require_relative ButterCut.engine_variant('resolve_legacy')
