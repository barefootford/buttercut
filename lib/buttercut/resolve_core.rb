require_relative 'fcp7'

class ButterCut
  # DaVinci Resolve timeline export. Resolve auto-corrects rotation from the
  # source file on import, so plain FCP7 xmeml works as-is — a named
  # pass-through subclass gives Resolve behavior a home if it ever diverges.
  class Resolve < FCP7
  end
end
