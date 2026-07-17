require_relative 'fcpx'

class ButterCut
  # DaVinci Resolve timeline export, riding the FCPX generator as a pure
  # pass-through — a named subclass gives Resolve behavior a home if it ever
  # diverges.
  class Resolve < FCPX
  end
end
