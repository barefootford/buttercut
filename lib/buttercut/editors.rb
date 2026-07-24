# frozen_string_literal: true

require_relative 'platform'

# The video editors ButterCut exports to, and which of them this machine can
# actually run. One owner, so the settings default, the export CLI and every
# skill that offers the user a choice all agree — offering Final Cut to a
# Windows user is a dead end that ends in an FCPXML they can't open.
#
# Kept apart from Export (which is the whole generator stack) so the CLI can
# answer "what are my options here?" cheaply.
module Editors
  # Display order, and the source of truth for what's offered. `resolve_legacy`
  # is deliberately absent: it's a fallback flag for older Resolve versions,
  # not a product anyone picks off a list.
  CHOICES = [
    { value: 'fcpx',     label: 'Final Cut Pro X',    mac_only: true },
    { value: 'premiere', label: 'Adobe Premiere Pro', mac_only: false },
    { value: 'resolve',  label: 'DaVinci Resolve',    mac_only: false }
  ].freeze

  module_function

  # The editors worth offering on this machine, as {value, label} — `mac_only`
  # is the filter, not part of the answer.
  def available
    CHOICES.reject { |choice| choice[:mac_only] && !Platform.mac? }
           .map { |choice| choice.slice(:value, :label) }
  end

  # What a fresh install should assume. Resolve off macOS: it's the one of the
  # two that's free and runs everywhere.
  def default = Platform.mac? ? 'fcpx' : 'resolve'

  def available?(editor) = available.any? { |choice| choice[:value] == editor.to_s }

  def find(editor) = CHOICES.find { |choice| choice[:value] == editor.to_s }

  def label(editor) = find(editor)&.fetch(:label)

  # Why an editor isn't usable here, phrased for the user, or nil if it is.
  # Exporting FCPXML from Windows for a colleague on a Mac is legitimate, so
  # this is a warning callers can print — never a hard stop.
  #
  # Silent for anything not on the list (`resolve_legacy`), which is a variant
  # of an available editor rather than a separate one.
  def unavailable_reason(editor)
    choice = find(editor)
    return nil unless choice && choice[:mac_only] && !Platform.mac?

    "#{choice[:label]} only runs on macOS, so this export won't open on this machine. " \
      "Use #{available.map { |option| option[:value] }.join(' or ')} for an editor you can open here."
  end
end
