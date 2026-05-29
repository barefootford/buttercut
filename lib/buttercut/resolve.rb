require_relative 'fcp7'

class ButterCut
  # DaVinci Resolve timeline export.
  #
  # Resolve imports the plain FCP7 (xmeml v5) interchange format as-is: it reads each
  # source file's own rotation flag on import and auto-corrects orientation, so vertical
  # footage stored as a rotated landscape frame comes in upright with no help from the XML.
  # That's why this is a thin pass-through over FCP7 while Premiere (which ignores the
  # source rotation flag) needs its own subclass that writes rotation explicitly.
  #
  # Keeping it as a named subclass — rather than pointing the factory straight at FCP7 —
  # gives Resolve-specific behavior a home if the two formats ever need to diverge.
  class Resolve < FCP7
  end
end
