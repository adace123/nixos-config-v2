# AI Coding Agents

Home-manager configures several AI coding assistants as CLI tools. All of it
lives under `modules/home/ai/`:

```text
modules/home/ai/
├── default.nix     # imports all agents below
├── claude.nix      # Claude Code
├── opencode.nix    # OpenCode
├── pi.nix          # Pi (pi-coding-agent) + its MCP + skills
├── hermes.nix      # Hermes (a Pi-compatible agent)
├── herdr.nix       # Herdr terminal multiplexer
├── shared.nix      # Shared rules / code-reviewer / commands across agents
└── skills.nix      # Skills synced from the mattpocock/skills flake input
```

Shell aliases (`modules/home/zsh.nix` / agent modules)

| Alias | Command |
|-------|---------|
| `cc` / `cca` | `claude --permission-mode=auto` / `claude agents` |
| `oc` | `opencode` |
| — | `pi` (Pi) |
| — | `hermes` |
| `ai-selector` | Interactive picker (see [scripts/README.md](../scripts/README.md)) |

## Shared configuration (`shared.nix`)

Defines cross-agent building blocks reused by Claude and OpenCode:

- **Rules** — `code-quality` and `best-practices` (loaded into each agent's
  context/instructions).
- **`code-reviewer` agent** — a senior-code-reviewer persona per agent.
- **`changelog` / `commit` commands** — conventional-commits style helpers.

Edit these once in `shared.nix` to change all agents that use them.

## Skills (`skills.nix`)

A curated set of agent skills is sourced from the **`mattpocock/skills`** flake
input so they stay in sync with upstream. The list currently includes
`productivity/grilling`, `productivity/grill-me`, and `engineering/tdd`.

- **Pi** gets them under `~/.pi/agent/skills/` (auto-discovered at startup).
- **Claude Code** gets the whole skill directory (including supporting files
  like `tdd`'s tests) via `programs.claude-code.skills`.

Add a skill by appending its `skills/<path>` to `commonSkills` in `skills.nix`.

- Pi-only skill: `commit-all` (a Nix-declared skill, not from upstream) is
  installed via `home.file` in `pi.nix`.

## Claude Code (`claude.nix`)

- Packages: `claude-code` (+ `ccstatusline`, `ccusage`).
- Defaults: `claude-sonnet-5`, `dark` theme, `auto` permission mode.
- **Status line** — running directory + git branch + `ccusage` usage.
- **MCP:** `context7` (HTTP).
- **Permissions** — whitelists common read/git commands, asks on writes/pushes.
- **PostToolUse hook** — auto-formats edited files by extension (`nix fmt`,
  `ruff format`, `dprint`/`prettier`, `markdownlint`, `yamlfmt`).
- Config is Nix-managed at `~/.claude/settings.json` (`force = true`).

## OpenCode (`opencode.nix`)

- Default model `opencode/deepseek-v4-flash-free`, MCP `context7` + `grep-mcp`.
- Granular permission presets (ask on writes/rm/dd, allow reads and git).
- Injects shared rules into its context and exposes the shared agents/commands.
- Config via `programs.opencode` (Nix-managed).

## Pi — `pi-coding-agent` (`pi.nix`)

Pi is a Rust-based conversational coding agent.

- Default provider `opencode-go` / model `deepseek-v4-flash`, thinking `high`.
- Ships many Pi packages/extensions (subagents, context-mode, todo, web-access,
  powerline footer, fff, etc.) — pins noted in `pi.nix` for reproducibility
  (some git/npm versions intentionally differ).
- **`~/.pi/agent/mcp.json`** — `context7` + `grep-mcp` (read by `pi-mcp-adapter`).
- **`~/.pi/agent/skills/`** — global auto-discovered skill location; populated
  with the shared skills plus the `commit-all` skill.
- **`~/.config/pi/web-search.json`** — TinyFish search config rendered at
  activation from the `tinyfish-api-key` SOPS secret. Note the path: because
  this machine sets `XDG_CONFIG_HOME`, the runtime reads `~/.config/pi/`, not
  `~/.pi/`.

## Hermes (`hermes.nix`)

- `config.yaml` (`~/.hermes/config.yaml`) and `.env` are **Nix-managed** — do
  **not** run `hermes config set KEY VAL` (the atomic-replace will fail on a
  store symlink).
- Default model `deepseek-v4-flash` via the `opencode-go` provider; holographic
  memory provider; manual approvals.
- Secrets (`opencode-api-key`, `opencode-zen-api-key`) injected into
  `~/.hermes/.env` from SOPS.

## Herdr (`herdr.nix`)

[Herdr](https://github.com/nikki93/herdr) is a terminal multiplexer that hosts
agents. `config.toml` is Nix-managed with a Catppuccin theme, pane/workspace
keybindings, and prefixed popup commands (lazygit, a Pi `commit-all` popup, and
a scratch shell).

## Adding / changing agents

1. Add/replace a module under `modules/home/ai/` and list it in `default.nix`.
2. Keep secrets out of the repo — reference SOPS placeholders
   (`config.sops.placeholder.<name>`) and declare the secret in `secrets.yaml`.
3. Any shared persona/rule change belongs in `shared.nix`.
4. Rebuild with `just switch`.

See [docs/darwin.md](darwin.md) for the shell/environment these agents run in.
