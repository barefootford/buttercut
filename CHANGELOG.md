# Changelog

All notable changes to ButterCut will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2025-01-21

### Added
- DaVinci Resolve support via FCP7 XML (xmeml version 5) format
- Release skill for automated version management and publishing workflow
- Centralized version management via `ButterCut::VERSION` constant

### Changed
- Improved library management with better documentation and workflow guidelines
- Enhanced CLAUDE.md with clearer library setup and parallel transcription patterns

### Fixed
- Gemspec now references version from `lib/buttercut/version.rb` for single source of truth

## [0.1.0] - 2025-01-15

### Added
- Initial release of ButterCut gem
- FCPX XML generation (FCPXML 1.8 format)
- FCP7/Premiere XML generation (xmeml version 5)
- Automatic video metadata extraction via FFmpeg
- Support for embedded SMPTE timecode
- Claude Code skills:
  - `transcribe-audio`: WhisperX-based audio transcription
  - `analyze-video`: Frame extraction and visual analysis
  - `roughcut`: AI-powered rough cut and sequence creation
- Library-based project management system
- Comprehensive test suite with 65+ specs
