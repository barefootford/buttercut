require_relative 'fcp7'

class ButterCut
  # Temporary fallback for DaVinci Resolve: the FCP7 xmeml export Resolve
  # exports used before the FCPXML migration (see resolve_core.rb). Kept
  # around for a couple weeks after that migration ships so an editor whose
  # Resolve install chokes on FCPXML import can still get a working export —
  # remove this file (and the `resolve_legacy` editor value) once FCPXML has
  # been in the field without incident.
  class ResolveLegacy < FCP7
  end
end
