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
├── herdr/          # Herdr terminal multiplexer
│   ├── herdr.nix   #   config.toml + picker plugin deployment
│   └── plugins/    #   installed .sh plugins
│       └── picker/ #   herdr-picker (generic fuzzy picker)
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

## Herdr (`herdr/herdr.nix`)

[Herdr](https://github.com/nikki93/herdr) is a terminal multiplexer that hosts
agents. `config.toml` is Nix-managed with a Catppuccin theme, pane/workspace
keybindings, and prefixed popup commands (lazygit, a Pi `commit-all` popup).

### Herdr Picker plugin

A `.sh` herdr plugin (`modules/home/ai/herdr/plugins/picker/`) — a generic
fuzzy picker over six categories, bound to **`ctrl+C`**
(`type = "plugin_action"`, action `herdr-picker.launch`):

- **spaces** — focus a herdr workspace
- **sessions** — attach to a named herdr session
- **tabs** — focus a herdr tab
- **worktrees** — open/focus a git worktree (scoped to the current repo)
- **commands** — run a custom command
- **agents** — focus a herdr agent pane

No argument = **menu** (pick a category, then an item); pass a category to jump
straight in. The picker opens as a **small centred popup**
(`placement = "popup"`) and everything **runs scoped to the current directory**
(captured from `HERDR_PLUGIN_CONTEXT_JSON`). The `tv` picker includes a preview
pane showing the selected label, source, and launch action; `fzf` remains the
fallback when `tv` is unavailable.

**Configuring the popup size** — the size is repo-managed in
`modules/home/ai/herdr/plugins/picker/config.toml`, copied to the plugin's config
dir on every activation (real, editable file):

```toml
[ui]
width = "70%"         # terminal cells (integer) or a percentage like "80%"
height = "70%"
close_on_exit = true   # false keeps the popup open until Enter
```

A command entry may override the default for itself:

```toml
[[keys.command]]
command = "just switch"
description = "build + activate darwin config"
close_on_exit = false
```

Commands come from two sources (project commands listed first):

- **Global** — `[[keys.command]]` entries in `config.toml` (the plugin's own
  keybinding is skipped).
- **Project** — a project-local `<repo>/.herdr-picker.toml` using the same
  format, discovered at the repo root (nearest git repo):

  ```toml
  [[keys.command]]
  command = "just check"
  description = "run checks"
  ```

The other categories are reachable as plugin actions too (`herdr-picker.spaces`,
`herdr-picker.sessions`, `herdr-picker.tabs`, `herdr-picker.worktrees`,
`herdr-picker.commands`, `herdr-picker.agents`), so you
can bind or trigger them directly.

Registration is handled automatically: a `home.activation` block copies the two
plugin files into a stable directory (`~/.config/herdr/plugins-managed/picker/`)
and runs `herdr plugin link` there if the plugin isn't already registered. A
plain `just switch` is all that's needed — no manual `herdr plugin link`.

(The copy-to-a-stable-dir step matters: `herdr plugin link` canonicalises the
linked path, so pointing it at a store symlink would go stale on every rebuild.)

## Adding / changing agents

1. Add/replace a module under `modules/home/ai/` and list it in `default.nix`.
2. Keep secrets out of the repo — reference SOPS placeholders
   (`config.sops.placeholder.<name>`) and declare the secret in `secrets.yaml`.
3. Any shared persona/rule change belongs in `shared.nix`.
4. Rebuild with `just switch`.

See [docs/darwin.md](darwin.md) for the shell/environment these agents run in.
