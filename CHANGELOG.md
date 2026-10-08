# Changelog

All notable changes to this configuration are recorded here. Versions are
**CalVer** — `YYYY.MM.DD`, plus a `.N` suffix for a second release on the same
day — and each version is cut at one commit on `main`: the promotion commit that
turns `[Unreleased]` into a heading. The rules for adding an entry, and the
commit kinds that are exempt, live in
[AGENTS.md → Changelog & Versioning](AGENTS.md#changelog--versioning).

## [Unreleased]

### Added

- feat(claude): route subagent models by role (Explore on Haiku 5.5, review on Sonnet 5.5)

### Changed

- refactor(kanban): move the board into its own repo and consume it as a flake input

### Fixed

- fix(claude): read auto-format hook input from stdin, register context7 at user scope, drop dead settings
- fix(claude): remove outputStyle, which matched no built-in style and had no effect

## [2026.10.07.3] - 2026-10-07

### Changed

- refactor(just): drop dead recipes and align update-input

## [2026.10.07.2] - 2026-10-07

### Fixed

- fix(commit-all): stop staging irrelevant files

## [2026.10.07.1] - 2026-10-07

### Added

- feat(just): add a release recipe

## [2026.10.07] - 2026-10-07

### Added

- docs(workflow): add CHANGELOG.md and require a per-commit entry
