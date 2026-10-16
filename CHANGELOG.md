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
- feat(just): notify on sudo auth during switch whether or not the lid is closed
- feat(pi): run pi update --extensions at activation
- feat(home): add OmniWM as the tiling window manager, replacing AeroSpace

### Changed

- refactor(kanban): move the board into its own repo and consume it as a flake input
- refactor(dathomir): boot an Oracle platform image and convert to NixOS in place
- chore(secrets): drop dathomir's revoked ts-auth-key

### Fixed

- fix(claude): read auto-format hook input from stdin, register context7 at user scope, drop dead settings
- fix(claude): remove outputStyle, which matched no built-in style and had no effect
- fix(dathomir): use the platform image's real disk labels, including /boot
- fix(dathomir): add the NAT gateway the public-IP-less instance needs for egress
- fix(secrets): replace dathomir's revoked Tailscale auth key
- fix(dathomir): make the conversion script executable
- fix(dathomir): read the Tailscale key file as root in the conversion guard
- fix(dathomir): mark the Tailscale state for preservation before nixos-infect runs

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
