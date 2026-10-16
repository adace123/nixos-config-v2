# Changelog

All notable changes to this configuration are recorded here. Versions are
**CalVer** — `YYYY.MM.DD`, plus a `.N` suffix for a second release on the same
day — and each version is cut at one commit on `main`: the promotion commit that
turns `[Unreleased]` into a heading. The rules for adding an entry, and the
commit kinds that are exempt, live in
[AGENTS.md → Changelog & Versioning](AGENTS.md#changelog--versioning).

## [Unreleased]

### Added

- feat(darwin): run Ollama as a per-user launchd agent, replacing LM Studio
- feat(claude): route subagent models by role (Explore on Haiku 5.5, review on Sonnet 5.5)
- feat(just): notify on sudo auth during switch whether or not the lid is closed
- feat(pi): run pi update --extensions at activation
- feat(home): add OmniWM as the tiling window manager, replacing AeroSpace
- feat(pre-commit): check that shebang scripts are executable
- feat(infra): refuse to destroy the converted dathomir instance by accident
- feat(dathomir): serve the beszel hub over the tailnet behind Caddy
- feat(infra): manage the ha and beszel DNS records in OpenTofu

### Changed

- refactor(kanban): move the board into its own repo and consume it as a flake input
- refactor(dathomir): boot an Oracle platform image and convert to NixOS in place
- chore(secrets): drop dathomir's revoked ts-auth-key
- chore(pre-commit): stop yamlfmt reformatting sops ciphertext
- refactor(caddy): share the Cloudflare-plugin Caddy build via nix-caddy.nix
- refactor(beszel): move the hub off the Pi hosts, add agents on dathomir and coruscant

### Fixed

- fix(claude): read auto-format hook input from stdin, register context7 at user scope, drop dead settings
- fix(claude): remove outputStyle, which matched no built-in style and had no effect
- fix(dathomir): use the platform image's real disk labels, including /boot
- fix(dathomir): add the NAT gateway the public-IP-less instance needs for egress
- fix(secrets): replace dathomir's revoked Tailscale auth key
- fix(dathomir): make the conversion script executable
- fix(dathomir): read the Tailscale key file as root in the conversion guard
- fix(dathomir): mark the Tailscale state for preservation before nixos-infect runs
- fix(dathomir): set NODE on the already-NixOS convergence path
- fix(just): pass the deploy target to nixos-remote-build positionally
- fix(darwin): install sofka as a homebrew-core formula, not a nonexistent cask
- fix(just): verify a deploy by the host's running generation, and accept a target
- fix(dathomir): cap boot generations so the 900MB /boot cannot fill
- fix(pre-commit): use `excludes`, the option git-hooks.nix actually reads

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
