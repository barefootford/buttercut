---
name: release
description: Creates a new ButterCut release with version bump, changelog, git tag, and GitHub release. Use when publishing a new version.
---

# Skill: Release ButterCut

Guides through the complete release process: version bump, changelog, git operations, and GitHub release creation.

ButterCut is distributed via `git clone` only. The `buttercut` gem on RubyGems was deprecated in 0.7.1 and is no longer published. Do not run `gem build` or `gem push` from this skill — those steps were removed.

## When to Use

- Publishing a new version of ButterCut
- After merging features or fixes that should be released

## Workflow

### 1. Run Tests First

**CRITICAL: Always run tests before releasing. Never release if tests fail.**

```bash
bundle exec rspec
```

If any tests fail, STOP immediately and ask user to fix before proceeding with release.

### 2. Check Current State

```bash
# Read current version
cat lib/buttercut/version.rb

# Check git status (must be clean)
git status

# Check existing tags
git tag -l
```

If git status is not clean, stop and ask user to commit or stash changes before proceeding.

### 3. Determine New Version

Ask user what type of release following [Semantic Versioning](https://semver.org/):
- **MAJOR** (1.0.0): Breaking changes
- **MINOR** (0.2.0): New features, backward compatible
- **PATCH** (0.1.1): Bug fixes, backward compatible

Calculate new version number based on current version and release type.

### 4. Update Version File

Edit `lib/buttercut/version.rb` with the new version:

```ruby
class ButterCut
  VERSION = "0.8.0"  # Update this
end
```

### 5. Update Gemfile.lock

Run `bundle install` so `Gemfile.lock` reflects the new version:

```bash
bundle install
```

Verify the version updated in `Gemfile.lock` before proceeding.

### 6. Gather Changelog Notes

Read the commits since the last tag (`git log --oneline v<last>..HEAD`) and group them by what they mean for the user. Ask the user to fill any gaps:
- What changed in this release?
- Any new features?
- Any bug fixes?
- Any breaking changes?

### 7. Update CHANGELOG.md

The changelog is customer facing. Readers are video editors, not engineers. Write every entry as the benefit the user gets, not the code that changed.

**Voice rules:**
- **Customer facing, not salesy.** Describe what the user can now do or what got fixed. No hype words ("blazing fast," "game-changing," "dramatically").
- **Straightforward.** Plain language. Say the thing.
- **AP Style.** Sentence case, serial commas, spell out numbers under 10, etc.
- **Active voice when possible.** "ButterCut opens your timeline" over "the timeline is opened."
- **No em dashes or en dashes.** Use a period, comma, or parentheses instead.
- **Editor vocabulary.** Talk like an editor (cut, sequence, timeline, footage, library), not a developer. Drop internal details, code symbols, file paths, and class names. If a change has no effect a user would notice (refactors, test coverage, repo cleanup), leave it out.

Prepend the new entry under `## [Unreleased]`. Group by `### New & Improved` and `### Fixed` (add `### Changed` only for user-visible behavior changes):

```markdown
## [0.8.0] - 2026-MM-DD

One or two plain sentences on what this release means for the user.

### New & Improved
- **Short benefit headline.** A sentence on what the user can now do.

### Fixed
- **Short benefit headline.** What used to go wrong, and that it now works.
```

### 8. Commit Version Bump

```bash
git add lib/buttercut/version.rb Gemfile.lock CHANGELOG.md
git commit -m "Bump version to 0.8.0"
```

### 9. Create and Push Git Tag

```bash
git tag v0.8.0
git push origin main
git push origin v0.8.0
```

### 10. Create GitHub Release

**Using GitHub CLI:**
```bash
gh release create v0.8.0 \
  --title "v0.8.0" \
  --notes "[Release notes from changelog]"
```

**If `gh` CLI not available:**

Guide user through manual release creation:
1. Go to https://github.com/barefootford/buttercut/releases/new
2. Choose tag: v0.8.0
3. Set title: v0.8.0
4. Paste changelog notes in description
5. Click "Publish release"

### 11. Verify Release

Check that everything worked:
- GitHub releases: https://github.com/barefootford/buttercut/releases
- Git tags: `git tag -l`

### 12. Return Success Response

Provide summary:
```
✓ ButterCut 0.8.0 released successfully

  Version: 0.8.0
  Git tag: v0.8.0
  GitHub Release: https://github.com/barefootford/buttercut/releases/tag/v0.8.0

Update existing installs with the `update-buttercut` skill, or:
  cd /path/to/buttercut && git pull
```

## Critical Principles

**Always run tests first** — never release if tests fail.
**Git must be clean** — no uncommitted changes before release.
**Push before publish** — tags must be pushed before creating the GitHub release.
**Semantic versioning** — follow semver strictly for version numbers.
**Changelog required** — every release needs documented changes.
**Do not publish to RubyGems** — the gem was deprecated in 0.7.1 and the gemspec has been removed from the repo. If you find yourself reaching for `gem build` or `gem push`, stop and re-read this skill.

## Common Issues

**Tests failing:** Ask user to fix tests before proceeding.
**Git not clean:** Ask user to commit or stash changes first.
**Tag already exists:** Verify this isn't a duplicate release.
**GitHub CLI not installed:** Provide manual release instructions.
