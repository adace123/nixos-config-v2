# Changelog

All notable changes to this configuration are recorded here. Versions are
**CalVer** — `YYYY.MM.DD`, plus a `.N` suffix for a second release on the same
day — and each version is cut at one commit on `main`: the promotion commit that
turns `[Unreleased]` into a heading. The rules for adding an entry, and the
commit kinds that are exempt, live in
[AGENTS.md → Changelog & Versioning](AGENTS.md#changelog--versioning).

## [Unreleased]

### Added

- feat(omniwm): bind Control+Option+Shift+R to rescue offscreen windows
- feat(darwin): run Ollama as a per-user launchd agent, replacing LM Studio
- feat(claude): route subagent models by role (Explore on Haiku 5.5, review on Sonnet 5.5)
- feat(just): notify on sudo auth during switch whether or not the lid is closed
- feat(pi): run pi update --extensions at activation
- feat(home): add OmniWM as the tiling window manager, replacing AeroSpace
- feat(pre-commit): check that shebang scripts are executable
- feat(infra): refuse to destroy the converted dathomir instance by accident
- feat(dathomir): serve the beszel hub over the tailnet behind Caddy
- feat(infra): manage the ha and beszel DNS records in OpenTofu
- feat(dathomir): add Pocket ID for passkey logins to the beszel hub
- feat(darwin): resolve DNS through Cloudflare's resolvers
- feat(beszel): enable agents on dathomir and coruscant with a universal token
- feat(beszel): run hub and agents from upstream 0.21.0 release binaries for the service-logs panel
- feat(omniwm): send Dia to the TV and pin Dia and Ghostty to their workspaces
- feat(omniwm): bind the bracket keys to the previous and next workspace
- feat(omniwm): bind Option+Q to close the focused window
- feat(omniwm): bind Option+S to the command palette
- feat(home): add android-tools for adb access to the Fire TV
- feat(omniwm): focus the browsers' workspace when the lid closes
- feat(omniwm): replace the two TV workspaces with one 📺 workspace

- feat(just): build NixOS configurations on dathomir instead of the target host
- feat(beszel): collect SMART in the agent on hosts that run smartd
- feat(beszel): back the hub's PocketBase state up to R2
- fix(beszel): initialise the hub's restic repository on first backup
- feat(darwin): build before switching and hand failures to pi in the agent and just switch
- feat(omp): manage omp via nix with glm-5.3-flash default and muse-spark-1.3 advisor
- feat(omp): use muse-spark-1.3 for the slow tier instead of glm-5.3 (latency)
- feat(darwin): add Numbers and HP Print and Support to the Mac App Store apps
- feat(omp): auto-approve the edit, write and ast_edit tools
- feat(omp): add context7 and grep-mcp MCP servers
- feat(omp): share the grilling and grill-me skills with omp
- feat(omp): derive a catppuccin theme with a visible user-prompt bubble
- feat(omp): use glm-5.3-flash as the advisor model
- feat(omp): fail over across providers with retry.fallbackChains
- feat(omp): enable local memory and the learn tool via autolearn
- feat(omp): share the commit-all skill with omp
- feat(omp): use the nerd status line with mouse and subagent previews
- feat(omp): bind Alt+[ and Alt+] to the tree branch jumps
- feat(omp): add the nixos MCP server to the repo-local .omp/mcp.json
- feat(tailscale): lock down tailnet with tag-based grants, Terraform-managed policy
- feat(dathomir): rewrite coruscant reachability check to tailscale ping + Caddy 443
- feat(pre-commit): lint GitHub workflows with actionlint and zizmor
- fix(dathomir): bind Pocket ID and its actors port to 127.0.0.1

### Changed

- refactor(kanban): move the board into its own repo and consume it as a flake input
- refactor(dathomir): boot an Oracle platform image and convert to NixOS in place
- chore(secrets): drop dathomir's revoked ts-auth-key
- chore(pre-commit): stop yamlfmt reformatting sops ciphertext
- refactor(caddy): share the Cloudflare-plugin Caddy build via nix-caddy.nix
- refactor(beszel): move the hub off the Pi hosts, add agents on dathomir and coruscant
- refactor(beszel): authenticate agents with a universal token instead of per-system keys
- chore(infra): commit the provider lockfile for the Cloudflare provider
- refactor(omniwm): drop app rules for apps that are not installed

### Fixed

- fix(nixos): stabilise the Pi hosts with an LTS kernel, chrony, a watchdog and no esphome
- fix(omniwm): put the TV workspace on the TV when the monitor is away
- fix(claude): read auto-format hook input from stdin, register context7 at user scope, drop dead settings
- fix(claude): remove outputStyle, which matched no built-in style and had no effect
- fix(dathomir): use the platform image's real disk labels, including /boot
- fix(dathomir): add the NAT gateway the public-IP-less instance needs for egress
- fix(secrets): replace dathomir's revoked Tailscale auth key
- fix(dathomir): make the conversion script executable
- fix(ha): keep zigbee2mqtt's coordinator alive by opening the device cgroup
- fix(ha): order zigbee2mqtt after mosquitto so the coordinator survives a boot
- fix(ha): point zigbee2mqtt at 127.0.0.1, because localhost resolves to ::1 here
- fix(just): verify a deploy against the flake's build, not the host's own profile
- fix(ha): make the restic jobs wait for the repo lock instead of failing
- fix(beszel): give the hub an APP_URL so alert links do not point at localhost
- fix(pi): harden the USB root path and add a storage canary that reboots on write failure
- fix(pi): disable the reboot watchdog explicitly instead of inheriting systemd's 10 min default
- fix(pi): keep automatic updates, backups and GC off the boot clock step, and verify the store weekly
- feat(beszel): check coruscant's reachability from dathomir every 10 minutes
- fix(dathomir): read the Tailscale key file as root in the conversion guard
- fix(dathomir): mark the Tailscale state for preservation before nixos-infect runs
- fix(dathomir): set NODE on the already-NixOS convergence path
- fix(just): pass the deploy target to nixos-remote-build positionally
- fix(omniwm): stop move.right and the layout toggle sharing Option+Shift+L
- fix(darwin): install sofka as a homebrew-core formula, not a nonexistent cask
- fix(just): verify a deploy by the host's running generation, and accept a target
- fix(dathomir): cap boot generations so the 900MB /boot cannot fill
- fix(pre-commit): use `excludes`, the option git-hooks.nix actually reads
- fix(dathomir-convert): refuse piped runs and say why a target is unreachable
- fix(beszel): keep the agents off until the hub can mint their keys
- fix(caddy): refresh the Cloudflare-plugin fixed-output hash
- fix(caddy): reload when the Caddyfile template changes, not just when a secret does
- fix(beszel): give agents the hub SSH public key (KEY), required alongside the universal token
- fix(beszel): give the agent journal access so service logs show in the hub UI
- fix(omniwm): split the workspace bar around the notch and auto-hide the macOS menu bar
- fix(darwin): pin cliamp's homebrew runtime libraries so cleanup stops zapping them
- fix(pre-commit): stop the gitleaks hook passing its own arguments twice
- fix(omniwm): rescue windows stranded on a display that disconnects
- fix(omniwm): keep the TV workspaces off the work monitor
- fix(omniwm): reserve layout space so windows clear the workspace bar
- fix(omniwm): widen the gap between the workspace bar and the window
- fix(omniwm): keep the gaps when a single window fills a workspace
- fix(omniwm): hide the workspace bar in native fullscreen
- fix(darwin): distrust the compromised eMudhra roots in the nix trust store
- fix(omniwm): drop the singleWindowFit value OmniWM cannot decode
- fix(omniwm): leave 1pt under the bar, even the notch gaps, halve the focus ring
- coruscant: cap journal, quiet Alexa logger, add SMART + voltage checks, trim recorder
- fix(pi): fail the under-voltage check so an alert can fire, not just a journal line
- fix(ci): require the flake checks and build the darwin configuration
- fix(omp): stop the setup wizard replaying after every switch and on every launch

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
