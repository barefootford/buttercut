class ButterCut
  # Distribution / identity for this build of ButterCut.
  #
  # This is the single place that knows how ButterCut is distributed and where
  # it lives. Isolating it here keeps the rest of the library free of
  # branding/URL details, so a fork only needs to change this one file.
  REPO_URL = "https://github.com/barefootford/buttercut".freeze
end

# The buttercut RubyGems gem was deprecated in 0.7.1; the XML generator now
# ships with the agent code in the repo. Warn only when loaded from a gem path.
if __FILE__.include?("/gems/buttercut-")
  warn "[buttercut] The buttercut gem is deprecated. The XML generator now ships with the agent code at #{ButterCut::REPO_URL} — clone the repo instead. The 0.7.x gem will keep working but will not be updated."
end
