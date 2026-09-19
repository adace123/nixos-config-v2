# AI Coding Agents

Home-manager configures several AI coding assistants as CLI tools. All of it
lives under `modules/home/ai/`:

```text
modules/home/ai/
├── default.nix     # imports all agents below
├── claude.nix      # Claude Code
├── opencode.nix    # OpenCode
├── pi.nix          # Pi (pi-coding-agent) + its MCP + skills
├── pi-extensions/  # Pi-only extensions (OpenCode session headers)
├── hermes.nix      # Hermes (a Pi-compatible agent)
├── herdr/          # Herdr terminal multiplexer
│   ├── herdr.nix   #   config.toml + plugin/extension deployment
│   ├── kanban-package.nix # packaging for the kanban board (Textual TUI)
│   ├── pi-extensions/ #  pi-side hooks (the pane state bridge)
│   └── plugins/    #   installed herdr plugins
│       ├── picker/ #   herdr-picker (generic fuzzy picker)
│       ├── automations/ # herdr-automations (cron-scheduled agent runs)
│       └── kanban/ #   herdr-kanban (board: workspace + agent tasks)
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
- **Git worktree rule** — Claude-only rule (defined in `claude.nix`, not
  `shared.nix`): implement features/fixes in a dedicated worktree, never
  commit directly on the default branch.
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
- **`~/.pi/agent/npm/.npmrc`** — pins `prefer-offline=false` for pi's own
  extension installs (`npm install --prefix ~/.pi/agent/npm`, where npm reads it
  as the project config), so `pi update --extensions` revalidates registry
  metadata even if `prefer-offline` is re-added user-wide. Why it matters: npm
  maps `prefer-offline=true` to HTTP cache mode `force-cache`, which serves
  cached metadata of any age, and the registry caches the full and compressed
  packuments separately (`vary: accept`) — so a stale full copy can advertise a
  `latest` version it does not contain and npm aborts with
  `ETARGET No matching version found for <pkg>@<version>`.
- **Extension updates** — run `pi-update` (a `pi update --extensions` alias that
  sets `NPM_CONFIG_PREFER_OFFLINE=false`); env config outranks `.npmrc`, so it
  stays authoritative even where a stale cache would otherwise win. To diagnose
  a recurrence, `just npm-cache-check` flags the precondition offline, and
  `npm cache verify` clears it (details in `scripts/README.md`).
- **`~/.pi/agent/mcp.json`** — `context7` + `grep-mcp` (read by `pi-mcp-adapter`).
- **`~/.pi/agent/skills/`** — global auto-discovered skill location; populated
  with the shared skills plus the `commit-all` skill.
- **`~/.pi/agent/extensions/opencode-session.ts`** — `pi-extensions/opencode-session.ts`
  via `home.file`; see [OpenCode session headers](#opencode-session-headers-pi-extensions).
- **`~/.config/pi/web-search.json`** — TinyFish search config rendered at
  activation from the `tinyfish-api-key` SOPS secret. Note the path: because
  this machine sets `XDG_CONFIG_HOME`, the runtime reads `~/.config/pi/`, not
  `~/.pi/`.

### OpenCode session headers (`pi-extensions/`)

OpenCode Go/Zen answer `400 MissingSessionID` to a request that does not carry
`x-opencode-session` — the id routes the conversation and keeps its prompt cache
warm ([opencode.ai/docs/go](https://opencode.ai/docs/go/#where-can-i-use-it)).
Pi sends it on its own requests: the agent loop passes its session id to the
model runtime, whose `transformHeaders` adds `x-opencode-session` /
`x-opencode-client`. That merge lives in the coding agent's stream wrapper, so
it covers only Pi's main request path.

An extension that runs a model **itself** — the shape needed to call a model
inside a tool call — goes through `ModelRuntime.completeSimple`, which applies
the provider's configured headers but never Pi's per-session ones. With an
`opencode-go` reviewer, `@juicesharp/rpiv-advisor` (2.10.1, latest) therefore
fails with `400 MissingSessionID` while the executor model works fine.
`modules/home/ai/pi-extensions/opencode-session.ts` closes the gap: on
`session_start` it registers `x-opencode-session` as a **provider header**
(`pi.registerProvider()` with headers and no `models` preserves the provider's
models and auth, and those headers are resolved into every request's auth
headers on *both* paths). The value is the session's own id — the same
`sessionManager.getSessionId()` Pi passes to its wrapper — so Pi's own traffic is
unchanged and extension side-calls start working. Providers outside OpenCode are
left alone.

Extensions load at Pi startup: restart Pi (or `/reload`) after a switch.
Verified in print mode — without the extension the advisor returns
`400 MissingSessionID`; with it, a real GLM-5.3-Flash answer (checked both loaded
with `-e` and auto-discovered from an `extensions/` directory).

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
keybindings, prefixed popup commands (lazygit, a Pi `commit-all` popup), and the
kanban board on **`prefix+k`** plus quick capture on **`ctrl+shift+k`** (see
[Herdr Kanban plugin](#herdr-kanban-plugin)).

### `config.toml` ownership and plugin-rewritten blocks

`xdg.configFile."herdr/config.toml"` makes `~/.config/herdr/config.toml` a
**read-only symlink into the Nix store**. Herdr itself is fine with that, but a
plugin that *rewrites* the file (herdr-radar, herdr-tsk, herdr-picker settings)
writes a temp file and renames it into place, which **replaces the symlink with
a real file**. Two consequences:

- The next `just switch` finds a real file where it expects its symlink, backs
  it up to `config.toml.bak` and restores the symlink — so everything the
  plugin wrote (including its managed blocks) is silently dropped, and only the
  keys in `herdr.nix` survive. Put anything you want to keep across a switch
  into `herdr.nix`, not the live file.
- Removing such a plugin without unwinding its config leaves **orphaned
  managed blocks** behind. Fenced `# >>> <plugin> … block` regions written by
  herdr-radar are the known case: they redefine `[ui.sidebar.agents]` /
  `[ui.sidebar.spaces]` rows using only plugin-supplied `$`-tokens (e.g.
  `$title_working`, `$space_label`). Herdr drops tokens whose metadata is never
  reported, and drops a row when none of its tokens have a value — so once the
  plugin stops reporting, Spaces and Agents render with **no titles at all**.

  Uninstall in the plugin's documented order (`herdr plugin action invoke
  hhdebb.herdr-radar.unconfigure` *before* `herdr plugin uninstall …`) so the
  blocks and tokens are cleared. To recover after the fact, delete the fenced
  blocks from `~/.config/herdr/config.toml` (or reinstall the plugin) and run
  `herdr server reload-config`; without those tables Herdr falls back to its
  built-in rows, which use `state_icon` / `workspace` / `agent` and always
  render. Herdr-radar also adds a `[ui] tab_bar_right` command that reads
  `~/.local/state/herdr/plugins/hhdebb.herdr-radar/tabbar.txt` every few
  seconds — that entry keeps failing in `herdr-server.log` until the block is
  removed.

### Herdr Picker plugin

A `.sh` herdr plugin (`modules/home/ai/herdr/plugins/picker/`) — a generic
fuzzy picker over eight categories, bound to **`ctrl+C`**
(`type = "plugin_action"`, action `herdr-picker.launch`):

- **spaces** — focus a herdr workspace
- **sessions** — attach to a named herdr session
- **tabs** — focus a herdr tab
- **worktrees** — open/focus a git worktree (scoped to the current repo)
- **files** — open a project file with `$EDITOR`
- **commands** — run a custom command
- **agents** — show agent cwd/status/workspace, then focus the agent
- **automations** — list scheduled automations (cron, workspace, agent, last
  run); selecting one fires it now (manual trigger)

No argument = **menu** (pick a category, then an item); pass a category to jump
straight in. The picker opens as a **small centred popup**
(`placement = "popup"`) and everything **runs scoped to the current directory**
(captured from `HERDR_PLUGIN_CONTEXT_JSON`). The `tv` picker includes a preview
pane showing the selected label, source, and launch action; in **files** mode it
previews the actual file contents instead (`bat` with line numbers when
available, plain `cat` otherwise). The `fzf` fallback gains the same file
preview in files mode.

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
`herdr-picker.files`, `herdr-picker.commands`, `herdr-picker.agents`,
`herdr-picker.automations`), so you
can bind or trigger them directly.

Registration is handled automatically: a `home.activation` block copies the two
plugin files into a stable directory (`~/.config/herdr/plugins-managed/picker/`)
and runs `herdr plugin link` there if the plugin isn't already registered. A
plain `just switch` is all that's needed — no manual `herdr plugin link`.

(The copy-to-a-stable-dir step matters: `herdr plugin link` canonicalises the
linked path, so pointing it at a store symlink would go stale on every rebuild.)

### Herdr Automations plugin

A `.sh` herdr plugin (`modules/home/ai/herdr/plugins/automations/`),
inspired by [herdr-shepherd](https://github.com/mikedclarke/herdr-shepherd):
run coding agents on a cron schedule. Each automation specifies a **cron
schedule**, **workspace**, **agent**, and **command** in a `[[automation]]`
block in its repo's `.herdr-automations.toml` (the legacy global dir
`~/.config/herdr/plugins/config/herdr-automations/automations/*.toml` still
works as a fallback; names must be unique across all sources):

```toml
[[automation]]
name = "morning-digest"
description = "Weekday tech-news briefing"  # optional: shown in list/picker/notifications
cron = "15 6 * * 1-5"          # 5-field cron (or @hourly/@daily/@weekly/@monthly/@yearly)
workspace = "ops"              # herdr workspace label (created if missing)
agent = "claude"               # herdr agent kind (claude | codex | pi | opencode | ...)
model = "sonnet"               # optional: --model for kinds that accept it
agent_args = ["--verbose"]     # optional: verbatim extra flags for the agent
command = "Prepare the morning digest per DIGEST.md."
directory = "~/projects/ops"   # optional cwd when creating the workspace
enabled = true                 # optional, default true (omitted = live)
auto_close = true              # optional: close the workspace when the run ends
watch_minutes = 240           # optional: stop watching after N minutes (default 240)
```

A daemon spawned by the plugin's `[[startup]]` hook ticks once a minute over
every repo in its registry (`automations.sh repos add <path>`; the wizard
registers automatically) plus the global fallback dir, and fires due
automations as visible herdr workspaces (resolve-or-create the
workspace, start the agent in a pane, submit the command), then leaves the
session open for review. Semantics mirror shepherd's: edits to the TOML files
apply within a minute with no restart, missed schedules are dropped (no
backfill after sleep/downtime), an automation never fires twice in the same
minute, and a manual run refuses while a scheduled run is still active.
A background watcher follows each scheduled run: one notification if the
agent blocks on input, `completed` / `attention` / `cancelled` recorded to
history (`auto_close` tidies the workspace on completion, `watch_minutes`
bounds the watch), and pre-start failures (herdr unreachable, prompt
rejected) retry on later ticks up to 3 attempts within 10 minutes.
A broken entry disables only itself (other blocks in the same file keep running)
and shows its error in listings. Each
run's pane gets `HERDR_AUTOMATION=<name>` and `HERDR_TRIGGER=<schedule|manual>`
in its environment.

```bash
# from inside herdr (the daemon needs herdr's socket env)
automations.sh daemon --detach  # start the scheduler (the startup hook does this)
automations.sh list             # table: name, schedule, enabled, last + next run
automations.sh status           # daemon liveness + the list
automations.sh run <name>       # fire now (manual trigger)
automations.sh open <name>      # focus the workspace of the last run
automations.sh history [name]   # newest-first run history
automations.sh show <name>      # details + run/enable/open actions
automations.sh board [--once]   # live htop-style table (static with --once)
automations.sh repos [add|remove <path>]  # repo registry
automations.sh enable <name> | automations.sh disable <name>
```

(The CLI lives at `~/.config/herdr/plugins-managed/automations/automations.sh`
after `just switch`.)

All automations are visible in the picker (`ctrl+C` → **Automations**, or the
`herdr-picker.automations` action), which shows each entry's description, cron, workspace,
agent, and last run. The list leads with a **+ board** row (live htop-style
table: vim navigation, run/enable/open keys, auto-refresh) followed by
**+ new automation…**, then one row per automation — selecting one opens a
details view (schedule, next run, history) with run/enable/open actions.
**+ new automation…** opens a guided creation wizard (schedule presets,
workspace/agent pickers, validation with the daemon's own parser) that appends
to the current repo's `.herdr-automations.toml` (registering the repo and
migrating any global automations in on first save), enabled from the start.
Same wizard via `automations.sh new`.
First run seeds a disabled
`example-cron.toml`; automation files are user data and are never overwritten
by later `just switch` runs.

### Pi pane state (`pi-extensions/`)

herdr's pi integration (`~/.pi/agent/extensions/herdr-agent-state.ts`, written
by `herdr integration install pi` and **herdr-managed — do not edit it**) reports
whether a turn is *running*, and that is all herdr's sidebar, `agent list` and
the kanban board know. Pi's `ask_user_question` runs **inside** a turn, so a pane
sitting on a questionnaire kept reporting `working`: the board's card stayed in
**In Progress** and the spinner never stopped, even though the agent was stopped
waiting on you.

`modules/home/ai/herdr/pi-extensions/herdr-ask-blocked.ts` is a **sibling**
extension — `home.file` → `~/.pi/agent/extensions/`, the place herdr's own file
header points extra hooks at — that translates
`@juicesharp/rpiv-ask-user-question`'s `rpiv:ask-user:blocked` event onto the
`herdr:blocked` channel the integration already consumes (the same channel
pi-subagents uses to report a run that needs attention). It raises at most once
per lower, labels the state with the question being asked, and clears on
`agent_settled` as a safety net, so the integration's count cannot stick.

So a waiting pane reads **Blocked** while the questionnaire is open and
**Working** again the instant you answer — which is exactly the transition the
board's Blocked ⇄ In Progress reconciliation watches for. Extensions load at Pi
startup: restart Pi (or `/reload` for an auto-discovered file) after a switch.

### Herdr Kanban plugin

A board for agent work: every card carries the workspace it belongs to, the
agent that should do it, and that agent's live state. Press `s` on a card and
the board opens a tab in that workspace, starts the agent there, and hands it
the task; found work becomes a linked card instead of a lost sentence in chat.

**It has its own manual: [docs/kanban.md](kanban.md).** The shortcuts worth
knowing from here:

- `prefix+k` — the board, as an overlay over the current pane
- `ctrl+shift+k` — capture a task in a popup; `^n` on that form saves **and**
  sends it in one keystroke
- `s` — send the selected card, `!` — show only the cards whose agents are
  waiting on an answer

## Adding / changing agents

1. Add/replace a module under `modules/home/ai/` and list it in `default.nix`.
2. Keep secrets out of the repo — reference SOPS placeholders
   (`config.sops.placeholder.<name>`) and declare the secret in `secrets.yaml`.
3. Any shared persona/rule change belongs in `shared.nix`.
4. Rebuild with `just switch`.

See [docs/darwin.md](darwin.md) for the shell/environment these agents run in.
