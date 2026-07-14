# Edition shim. Core Resolve rides the FCP7 (xmeml) generator; Pro rides the
# FCPX generator instead — FCPXML is the only interchange format that lands a
# real multicam clip in Resolve. See ButterCut.engine_variant in
# lib/buttercut/version.rb.
require_relative 'version'
require_relative ButterCut.engine_variant('resolve')
