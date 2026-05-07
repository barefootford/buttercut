---
name: release
description: Creates a new ButterCut release with version bump, changelog, git tag, gem build, and GitHub release. Use when publishing a new version.
---

# Skill: Release ButterCut

Guides through the complete release process: version bump, changelog, git operations, gem publishing, and GitHub release creation.

## When to Use

- Publishing a new version of ButterCut
- After merging features or fixes that should be released
- Creating the first v0.1.0 release

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
  VERSION = "0.2.0"  # Update this
end
```

### 5. Update Gemfile.lock

Run `bundle install` so `Gemfile.lock` reflects the new version:

```bash
bundle install
```

Verify the version updated in `Gemfile.lock` before proceeding.

### 6. Gather Changelog Notes

Ask user for release notes. Prompt with:
- What changed in this release?
- Any new features?
- Any bug fixes?
- Any breaking changes?

### 7. Update or Create CHANGELOG.md

If `CHANGELOG.md` exists, prepend new entry. Otherwise create it:

```markdown
# Changelog

All notable changes to ButterCut will be documented in this file.

## [0.2.0] - 2025-01-21

### Added
- Feature X
- Support for Y

### Fixed
- Bug in Z

### Changed
- Improved W
```

### 8. Commit Version Bump

```bash
git add lib/buttercut/version.rb Gemfile.lock CHANGELOG.md
git commit -m "Bump version to 0.2.0"
```

### 9. Create and Push Git Tag

```bash
git tag v0.2.0
git push origin main
git push origin v0.2.0
```

### 10. Build Gem

```bash
gem build buttercut.gemspec
```

This creates `buttercut-0.2.0.gem` file.

### 11. Publish to RubyGems

**First time setup check:**

If this is the first release, verify RubyGems authentication:
```bash
gem signin
```

If not authenticated, provide instructions:
1. Sign up at https://rubygems.org
2. Run `gem signin` and follow prompts
3. Store credentials for future releases

**Publish the gem:**
```bash
gem push buttercut-0.2.0.gem
```

This makes the gem available for `gem install buttercut` worldwide.

### 12. Create GitHub Release

**Using GitHub CLI:**
```bash
gh release create v0.2.0 \
  --title "v0.2.0" \
  --notes "[Release notes from changelog]" \
  buttercut-0.2.0.gem
```

**If `gh` CLI not available:**

Guide user through manual release creation:
1. Go to https://github.com/andrewford/buttercut/releases/new
2. Choose tag: v0.2.0
3. Set title: v0.2.0
4. Paste changelog notes in description
5. Attach buttercut-0.2.0.gem file
6. Click "Publish release"

Then wait for user confirmation that release is created before proceeding to cleanup.

### 13. Cleanup

```bash
# Remove local gem file (it's on RubyGems and GitHub now)
rm buttercut-0.2.0.gem
```

### 14. Verify Release

Check that everything worked:
- RubyGems page: https://rubygems.org/gems/buttercut
- GitHub releases: https://github.com/andrewford/buttercut/releases
- Git tags: `git tag -l`

### 15. Return Success Response

Provide summary:
```
✓ ButterCut 0.2.0 released successfully

  Version: 0.2.0
  Git tag: v0.2.0
  RubyGems: Published at https://rubygems.org/gems/buttercut
  GitHub Release: https://github.com/andrewford/buttercut/releases/tag/v0.2.0

Installation:
  gem install buttercut

Upgrade:
  gem update buttercut
```

## Critical Principles

**Always run tests first** - Never release if tests fail
**Git must be clean** - No uncommitted changes before release
**Push before publish** - Tags must be pushed before creating GitHub release
**Semantic versioning** - Follow semver strictly for version numbers
**Changelog required** - Every release needs documented changes

## Common Issues

**Tests failing:** Ask user to fix tests before proceeding
**Git not clean:** Ask user to commit or stash changes first
**Tag already exists:** Verify this isn't a duplicate release
**RubyGems authentication:** Guide through `gem signin` process
**GitHub CLI not installed:** Provide manual release instructions
