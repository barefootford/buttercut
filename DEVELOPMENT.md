# Developing ButterCut

For sessions in developer mode (`.buttercut_mode` says `developer`). Everything in `AGENTS.md` still applies; this page adds what only matters when you're changing ButterCut itself.

## Changelog and versions

ButterCut has no version numbers and no release step: users get whatever is on `main`.

- **Add a changelog line when a video editor would notice the change.** It goes in `CHANGELOG.md` under the current month's heading (`## November 2026`), written in the editor's language. Start a new heading at the top when the month changes. Refactors, tests and other internal work get no line.
- **Nothing to bump.** `lib/buttercut/version.rb` reads the newest month heading: `ButterCut::RELEASE` is `November 2026` and `ButterCut::VERSION` is `2026.11`. Bug reports send the version and the install's commit, which says exactly which build failed.
