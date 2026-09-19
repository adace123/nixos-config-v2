# Herdr Kanban board

`herdr-kanban` is a board for agent work inside [herdr](ai.md#herdr-herdrherdrnix):
every card carries the workspace it belongs to, the agent that should do it, and
the live state of that agent. It is a herdr plugin, deployed by `herdr.nix` from
`modules/home/ai/herdr/plugins/kanban/`, with a Python TUI packaged by
`kanban-package.nix`.

This is the board's own manual. [docs/ai.md](ai.md) covers the agents and the
herdr plugins around it.

Two shortcuts open it:

| Key | Action | Opens as |
| --- | --- | --- |
| **`prefix+k`** | `herdr-kanban.open` — the board | full-pane **overlay** |
| **`ctrl+shift+k`** | `herdr-kanban.quick-add` — capture a task | centred **popup** |

The split is deliberate: the board is somewhere you go to think, so it takes the
screen and restores your focus when you leave; capture should cost you nothing,
so it is a popup seeded from the workspace you are in — `ctrl+shift+k`, type,
`⏎` (or `^n` to save and start the agent at once). Both actions are
`type = "plugin_action"` entries in `herdr.nix`. The popup saves
with `⏎` in the title field, and confirms itself with a herdr notification
(`herdr notification show`), because a popup that closes on save has nowhere
left to show a toast.

Quick capture's geometry is its own (`quick_add_placement` / `quick_add_width` /
`quick_add_height`, defaulting to a `popup` at 80%×75%) so it stays a popup even
if you make the board an overlay; the board's `placement` is unset by default,
which leaves the manifest's `overlay` in charge.

Every card carries **the workspace it belongs to, the agent that should do it,
and what that agent is doing right now** — the agent's own mark and kind on the
meta row, the live state spelled out on the rule below it, so one board shows
the work of every workspace at once:

```text
▦ Kanban  ·  all workspaces                                                8 tasks  ● 2 working  ▲ 1 needs you
▎Backlog     2▾ ▸ ▎Queued        2▾ ▎In Progress   2▾ ▎Blocked        0 ▎Review         1 ▎Done           1
╭ cfg-1 ▲───────╮ ╭ pers-5 ───────╮ ╭ cfg-3 ✎───────╮                   ╭ argo-4 ───────╮ ╭ snow-7 ───────╮
│ Fix flake     │ │ Bump the pi   │ │ Add herdr     │                   │ Review the    │ │ Write release │
│ lock drift a… │ │ package pins  │ │ kanban board… │ ·                 │ tsk board in… │ │ notes for th… │
│ ▪ nixo… 10m π │ │ ▪ pers… 10m Ʌ │ │ ▪ nixo… 2/3 π │                   │ ▪ argo  10m Λ │ │ ▪ snow… 10m ✦ │
╰───────────────╯ ╰───────────────╯ ╰── ◐ working ──╯                   ╰── ○ idle ─────╯ ╰── ∅ no agent ─╯
```

**Card anatomy** — every line of a card has one job, and the same job on every
card, so a column can be read without reading it:

| Where | What |
| --- | --- |
| `cfg-3` in the top rule | the id — the workspace it was filed in, then the board's counter (**Ids** below). Tinted while an agent has the card: yellow working, grey idle, dimmer still for one that exited. Blocked and done leave it alone — they already colour the whole border — and a live status outranks a stale age. |
| `▲` before the title | priority: `▲` high, `‼` urgent, `▽` low, nothing for normal. |
| `✎` after it | the agent named this card (`ui.show_agent_kind` off does not hide it; the capture title is in `⏎`). |
| first line(s) | the title, two rows, ellipsised. |
| `▪` + label | the workspace, with the dot in that workspace's colour. `⚠` and a red label when the workspace is closed. |
| meta row, right | step progress (`2/5`), age, then the agent's mark (`π`) — and its kind (`π pi`) when `ui.show_agent_kind` is on. |
| bottom rule | the live state, in words: `◐ working`, `▲ needs you`, `○ idle`, `✓ done`, `∅ no agent`. |

The placement is deliberate: a card answers "which of these needs me" before it
answers "what is it", which is the order you scan a board in. The rule along the
bottom is where the live state goes because it is the one line with room at every
column width — in the meta row a status word only survived on a 210-column
terminal.

The **agent mark** (`π`) comes from `task.agent_kind` when the board did the
dispatching; for an agent started by hand the live agent's own mark
(`harness_logo`) and title are asked instead, and only then the card's title —
which is why the kind is *spelled out* at all on the wide columns: a wrong guess
is visible rather than silent. The mark is always drawn and always tinted with
the vendor's colour, so a card is identifiable without the name; `ui.show_agent_kind`
is what puts the name beside it, and it is off by default because those four to
eight cells are worth more to the workspace label and the age. The name is still
in the detail view, in both agent pickers, and in `list`/`show`.

**Keys** — `h`/`l`/`tab` columns, `j`/`k` cards, `g`/`G` first/last, `1`-`9`
jump to a column, `H`/`L` move a card between columns, `J`/`K` reorder inside a
column, `⏎` detail (with the agent's recent output), `a` add, `e` edit, `d`
delete (which also stops its agent), `A` archive (kept off the board, its agent
left running), `x` stop the agent but keep the card, `s` send,
`!` show only the cards whose agents are waiting on you, `f` focus the agent,
`o` focus the workspace, `p` focus the pane, `/` filter, `w` cycle the workspace
filter, `c` clear every filter, `r` refresh, `?` help, `q` quit, and `1`-`9` in
the detail view tick that checklist entry — `ctrl+c` quits too, from anywhere,
dialogs included (Textual's own "press q to quit" toast is overridden, because
inside an overlay a key that only says that reads as a key that does nothing).
Clicking selects, double-clicking opens the detail, the wheel scrolls a column;
a column heading with `▴` or `▾` beside its count has cards off screen either
way. Moving a card with `H`/`L` says so in the footer with both ends of the move
— `cfg-3 · Backlog → Queued` — because on a busy board the destination alone does
not say where the card came from.

A card's **meta row** reads workspace, step progress (`2/5`), age, then the
agent's mark; the age is tinted once a card passes `stale_after_days`.
The tokens at the right-hand end are dropped as a column narrows, in the order
they matter least: the age, then the step counter, then the kind, then the mark.
The workspace label is never dropped, it truncates. The id badge works the other
way round: a card too narrow for `snowfl-7` drops the *code* and keeps the
counter (` 7 `) rather than let a badge push the rule's `╮` off the card, since
the meta row underneath already names the workspace in full.

**Ids** are `<code>-<counter>` — `cfg-8`. The code names the workspace the card
was *filed* in, which is what makes an id worth reading: `herdr-kanban show
snow-7` places a card without opening the board, and the dispatch prompt
(`this card is cfg-8`) carries the same label into the pane. The counter is
board-wide and only ever grows, so a number alone names exactly one card on the
board (`herdr-kanban status 8 review`), and a card with nothing to code from
keeps the plain `K8` it would have had before codes existed — filed with no
workspace at all, or into a workspace whose label is unknown and whose herdr id
is the only name left (`w1-7`).

The code is the label's own slug, cut to six characters (`nixos-config-v2` →
`nixos`, `snowflake-reporting` → `snowfl`), so ids work with no configuration at
all. `[workspaces]` in `config.toml` overrides it — by label, or by herdr's
workspace id (`w1 = "cfg"`) so that a `herdr workspace rename` cannot change it
— and is worth the ten seconds for a label whose slug is ugly or ambiguous. Two
workspaces whose labels start alike get alike codes; the ids stay unique (the
counter is shared), but the alias is how you tell them apart at a glance.

A code is frozen when the card is filed and never follows the card. A dispatch
into another workspace, or a rename of the workspace itself, leaves the id alone:
an id is a name other cards, panes and prompts already hold, so the card's
*live* workspace is what its meta row shows (`▪ work`) while the id keeps saying
where the work came from — the same division as `found during cfg-1` and the rest
of the card's history. Cards filed before this existed keep their `K` ids, and
every lookup that took `K3` takes `cfg-3` — or `CFG-3`, or just `3`, because an
id is matched without regard to case and the counter alone is unambiguous.

The **`!` view** is the answer to the header's `▲ 1 needs you`: one keystroke
shows only the blocked cards, from every workspace at once, with the hidden count
in the header (`8 tasks (7 hidden)`). It is a filter like any other, so `c`
clears it and the header says `needs you` while it is on. Because it is computed
from live state, a card appears the moment its agent blocks and leaves the moment
you answer it.

The filter is ANDed words against title, notes, labels, workspace and agent —
and `"a quoted phrase"` is matched as one term, which is how you search for a
sentence out of a note. The detail view (`⏎`) is a **watch view**: it re-reads
the card, its steps and its live agent state on the board's `sync_seconds` tick,
and the agent's recent output every third tick, so you can leave it open and
watch a run progress. Sending a card (`s`) warns you first if the column it
would land in is already at its `wip_limits`.

**The detail view** (`⏎`) is the card's whole record, in sections that only
appear when they have something to say: the facts (column, agent, state,
workspace, pane, ages), Notes, Steps, **Updates** (what the agent chose to say,
via `herdr-kanban note`), **History** (what the board recorded — who filed it,
every column it has been in, every rename, and by whom), and the agent's live
output on `r`. Two rows connect it to other cards: `found    while working on
cfg-1` for a card that came out of another one, and `spawned  snow-7 (Backlog)`
for the cards it produced. History is capped at the last 25 entries on disk and the last
12 are shown.

**Sending a card** (`s`) opens a form (editable prompt, workspace, agent kind,
agent name, worktree) and then: create a tab in the card's workspace (or in a
worktree forked for it — see below), run
`agent start <task-id> --kind <kind> --pane <pane>`, and `agent prompt` it with
the task's title, its notes, and the board protocol below. The card records the
pane and tab, and from then on mirrors the agent's real state. Sending again to a
card whose agent is still running prompts that agent instead of starting another
one.

The tab exists to host the agent, not to be a dev session, so the board creates
it with `HERDR_KANBAN_DISPATCH=1` in its environment (`dispatch.DISPATCH_ENV`)
and `modules/home/zsh.nix` skips the direnv hook and the fastfetch banner when it
is set. A repo with a dev shell — this one — would otherwise pay
`nix print-dev-env` and print the dev-shell banner into the pane before every
agent start, and the neofetch card would scroll the pane the agent is about to
use out from under it. The skip takes the whole
`.envrc` with it, `.env` included: a dispatched agent runs with the environment
its pane inherited, not with your secrets.

Where a send *puts* the card does not depend on where it came from: a send
starts (or re-prompts) the card's agent and only reports success once the agent
has actually begun a turn, so the card is in **In Progress** the moment the
dispatch returns — a card that was just sent is never left in **Queued**.
**Queued** is a column you park committed-but-unstarted work in by hand; the
board does not dispatch anything into it, and if a card sitting in one turns out
to have a working agent the board moves it to In Progress on the next tick
rather than leave a "waiting for an agent" label on a card whose agent is at
work. The target is the column with `role = "doing"` (`Config.send_column`),
falling back to a matching id (`doing`/`in-progress`/`progress`/`started`), so a
board that calls its columns `later`/`next`/`started` lands sends in `started`,
and a board with no In Progress column leaves the card where it is. `wip_limits`
are checked against the column the send would land in.

**Send now.** The add form has its own shortcut — `^n`, or the **Send now**
button — which saves the card and starts its agent in one keystroke, skipping the
dispatch form: the form has already asked for the workspace and the agent kind,
so making you confirm them is a dialog for the sake of a dialog. The edit form
has neither the button nor the behaviour (`^n` there just saves; re-prompting a
running agent is the board's `s`). It is the same dispatch under the hood, so the
card lands in the column the rule above picks, records its pane and tab, and
every later dispatch still goes through the form.

**The Model field** under Agent is optional and defaults to `default`, which
means "say nothing about the model": `[agents.<kind>] args` already carries
whatever you run that CLI with interactively, and a card should not have to
repeat it. The names offered come from a `[models]` list per kind
(`config.toml`), because there is no registry to look them up in — each CLI has
its own names and only you know them. Switching the agent changes the list, and a
model the newly chosen agent has no entry for falls back to `default` rather than
being sent to a CLI that will not understand it.

What the card asks for then *replaces* a `--model` pair in the kind's configured
args, rather than adding a second one: `[agents.pi] args = ["--model",
"deepseek-v4-flash"]` plus a card on `glm-5.3-flash` runs with `--verbose --model
glm-5.3-flash` and never with two `--model` flags, which would be a last-wins
coin toss. `--model=sonnet` is recognised as the same flag spelled the other way.
A name the CLI rejects fails at `agent start`, where the board reports the step
that broke and leaves the card where it was — which is also why the list is worth
keeping honest instead of guessed at.

**A worktree per card.** The send form's **Git worktree** option forks the repo
the card sits in into a checkout of its own — `herdr worktree create`, which also
opens it as a herdr workspace — and starts the agent there instead of in the
shared checkout. Two cards on one repo then cannot step on each other's working
tree, which is the whole reason it exists: the board is where several agents run
at once, and a repo has one index. `worktree` in `[behavior]` only decides
whether the option starts ticked; a card that already owns a checkout always
offers it ticked, because the checkout is where its work lives.

The card records the checkout (`worktree_path`), its branch (`worktree_branch`)
and the workspace herdr opened for it (`worktree_workspace_id`), while its
`workspace` stays the repo it was forked *from* — so the id it was filed with,
and the next dispatch's fork point, still point at the same place. A re-dispatch
**reuses** the card's checkout, reopening it if its workspace was closed, rather
than forking a second one: one card, one working tree. The detail view shows the
path and branch, and so do `show` and `list --json` (`worktree_path`,
`worktree_branch`, `worktree_workspace`).

Deleting a card that has a checkout asks a second time, after the delete
confirmation: *Also remove the worktree for cfg-8?* Removal closes the workspace
herdr opened for it (`herdr worktree remove --workspace`), so a workspace you
closed by hand first cannot be removed this way — the board says so and names
the `git worktree remove <path>` that will. The question is a second
confirmation rather than a config key because the checkout is the only thing
that remembers where a card's uncommitted work is, and once the card is gone
nothing in herdr points at it. If the card's agent is kept
(`auto_delete_agent = false`) the checkout stays with it, because it *is* the
agent's workspace.

`agent prompt` reports success once the text *and* the Enter have been written,
which is not the same as the agent acting on them: prompt an agent in the moment
between herdr detecting it as ready and its input handler coming up, and the text
is left sitting in the composer with the agent idle forever. pi does this
intermittently. So the board **confirms the turn started** — an agent lifecycle
change within a few seconds — and if it did not, submits the text with a bare
Enter (what you would press) and only then reports failure. A dispatch that never
started leaves the card where it was rather than claiming it is in progress, and
tells you the pane is open with the text in it.

**Stopping an agent.** A card is the record of a run, so `d` (delete) stops the
agent and closes the tab its dispatch opened, as part of deleting. Set
`auto_delete_agent = false` to delete the card and keep the agent — the board
names which it will do in the confirmation either way. `x` does the same
without deleting the card, which is what you want for a runaway run. Both
confirm first, and both leave a tab alone if its label is no longer the one the
board last wrote to it — that pane is yours now, not the card's.

**Delete vs archive.** `d` deletes: the card and its record go. `A` archives:
the card leaves the board and joins an `archived` list in `board.json`, keeping
everything it had plus the time and the column it left. Archiving deliberately
does **not** touch the run — a card whose agent is still going keeps its agent
and its tab, and the notice says so, because the record of a run should outlive
its place on the board. `herdr-kanban unarchive cfg-8` puts it back at the end
of the column it came from, and `herdr-kanban list --archived` shows what is in
there; an archived card is still `show`-able and still answers to its id or its
number. `A` asks nothing first — unlike `d`, nothing is lost — and the footer
names the `unarchive` that undoes it.

**Live state** is polled from `agent list` every `sync_seconds` (two by
default), and `workspace list` on its own slower clock — workspaces are opened
and closed by hand a few times an hour, and every read is a herdr subprocess, so
there is no reason to ask on every tick. From that, the rule at the bottom of
each card spells out `⣷ working`, `▲ needs you`, `○ idle`, `✓ done`, or
`∅ no agent`; the id badge is tinted for the states the border has no colour for;
a task whose workspace is no longer open gets a red `⚠` in front of its label
instead of the dot. `✎` in a card's border means the agent named it. Cards are
matched to agents **by pane ID**: herdr reports the *kind* (`pi`) as an agent's
label when it was started without a name, so the pane is the only dependable
link between a card and its agent.

**When an agent blocks, the card moves to Blocked and herdr says so.** Blocked
is the one state that costs something to ignore — the agent is stopped until you
answer — and both places that show it require looking at the board. So the board
puts a card whose agent has stopped to ask you something into **Blocked**,
wherever it was, and the first time a card *arrives* in that state it raises a
herdr notification **and** a desktop notification (`work-6 needs you`, with the
title). Answer the question and the agent starts working again, which carries the
card back to **In Progress**. The trigger is herdr's own `agent_status`, not a
peek at the pane: the board believes `blocked` when herdr reports it, so the
pane has to be honest first — for a Pi agent that means the sibling extension
that turns the questionnaire's `rpiv:ask-user:blocked` into herdr's
`herdr:blocked` ([docs/ai.md](ai.md#pi-pane-state-pi-extensions)). Only
transitions are announced: a board that opens onto a blocked card stays quiet,
because nothing has changed since you last looked. `notify_on_block = false`
turns the whole thing off, and `notify_system = false` keeps the herdr toast but
drops the desktop banner.

**When an agent files a card, the desktop says so.** Filing a new card is how an
agent reports work it found while doing something else (see below), and it is the
one way a card arrives without you having asked for it. So `herdr-kanban add`
raises a desktop notification — `cfg-8 filed`, with the card's title, and
`· found during cfg-3` when the card it came out of is known. It comes from the
CLI rather than the board, because the agent runs the command whether or not the
board is open, and those are the times you are not looking at either. Nothing is
announced for a card that does not claim an agent filed it — the same
`created_by` test the rest of the board uses, caveat included: a person who runs
`add` from a herdr pane is recorded as an agent, and is announced as one. No
herdr toast goes with it, because a toast reaches someone already looking at
herdr, who is about to watch the card appear anyway. `notify_on_add = false`
silences it, and so does `notify_system = false` — a banner is the only form this
one takes.

## How cards get updated

A dispatched agent keeps its own card current through the same binary you run.
`config.toml`'s `announce_protocol` (on by default) appends this to the prompt:

```text
---
herdr kanban: this card is cfg-3. Keep it current as you work:
  finished?        herdr-kanban status review
  waiting on me?   herdr-kanban block "what you need"
  worth noting?    herdr-kanban note "what you found or changed"
  name this card:  herdr-kanban title "<concise title, once you know the real work>"
  found more work? herdr-kanban add "<title>" --notes "why it is separate"
Run those from this pane — no task id needed, the board finds the card by its
pane; only I close cards. If you find unrelated work, add a card for it instead
of doing it here; if the board says a card already covers it, note that one
instead of filing a second.

Your turn is not over until the card is moved — `note` records progress, it does
not move the card, and a turn that only notes leaves the card saying you are
still working. Move it before your final message:
  task done, even if you offer to do more -> herdr-kanban status review
  stopped, cannot continue without me     -> herdr-kanban block "what you need"
  still working                           -> leave it; the card stays In Progress
```

The closing block is the one part that is a requirement rather than a verb
table. `note` records progress and never moves a card, so an agent that notes its
findings and stops leaves the card claiming to be in progress — the failure that
put a finished card in In Progress behind a green `✓ done` border. The *closing
offer* case is spelled out because an agent ending its turn with "want me to do
more?" is finished, not blocked, and would otherwise reach for neither verb.

Those commands resolve the card from `HERDR_PANE_ID` (herdr injects it into
every pane, and the board records it on dispatch), so an agent is never told an
id it has to carry around. `herdr-kanban --help` prints this verb table and the
protocol — the same text `herdr-kanban help` gives — before the board's own
flags, so an agent that checks its tools finds the commands its prompt names
rather than a TUI's options. Humans run the same verbs with an explicit id — the
full `cfg-8`, or just the number `8`, which is unique board-wide:

| Command | Effect |
| --- | --- |
| `herdr-kanban status [<task>] <column>` | move a card (id, number, or this pane) |
| `herdr-kanban block [<task>] [why]` | park it in Blocked and record why |
| `herdr-kanban note [<task>] <text>` | append to the card's **Updates** (shown in `⏎`) |
| `herdr-kanban title [<task>] <text>` | name the card, within the policy below |
| `herdr-kanban step [<task>]` | the card's checklist |
| `herdr-kanban step [<task>] add <text> \| done <n> \| undo <n> \| rm <n>` | change it |
| `herdr-kanban add <title> [--workspace <id>] [--agent <kind>] [--column <col>] [--notes <text…>] [--from <task>] [--model <name>] [--force]` | file a **new** card, linked to the one that found it |
| `herdr-kanban send [<task>] [--agent <kind>] [--workspace <id>] [--model <name>] [--worktree\|--no-worktree] [--dry-run]` | start an agent for a card, without the board |
| `herdr-kanban list [--mine] [--archived] [--json]` | the board (or just this pane's card), or the archive |
| `herdr-kanban show [<task>] [--json]` | one card in full, history included (an archived card too) |
| `herdr-kanban archive [<task>]` | take a card off the board, keeping its record |
| `herdr-kanban unarchive [<task>]` | put an archived card back in the column it left |

`add` exists so an agent that finds *more* work has somewhere to put it, rather
than doing it out of scope or mentioning it in chat and losing it. It defaults
the workspace to the one the caller is running in, the column to
`default_column`, the agent to `default_agent`, and prints the new card's id.
`--notes` is free text, the same as `note`: it takes every following word up to
the next `-`-prefixed token, so `--notes why it is separate` needs no quotes and
`--notes why --priority high` still reads `--priority` as a flag rather than part
of the note. A `-`-word that is not a known flag ends the note and is reported as
an unknown option instead of being silently swallowed.

**A card knows where it came from.** `--from cfg-3` records which card the work fell
out of, and an agent does not even have to say it: the pane an agent works in *is*
a card, so `herdr-kanban add` from that pane links the new card back to it
automatically. The detail view then reads both ways — `found  while working on
cfg-3` on the new card, `spawned  snow-7 (Backlog)` on the old one — and `list`
shows `· found during cfg-3`. The reason is the one thing a follow-up loses the
moment it is filed: after the run that produced it is over, "why did I want
this?" is otherwise unanswerable.

Two guards keep the backlog from filling with the same thought twice. A title
that already exists is **refused**: matching ignores case and runs of
whitespace, so an agent writing from memory still hits the existing card, and
the message names it (`cfg-3 already covers this: "…" (Backlog)`) and points at
`--force` for the genuine case of two cards that share a title. A card filed from
the CLI also **records where it came from** — `created_by`, shown as
`filed by an agent` in `list`/`show`/`--json` and as `created 2h ago by an agent`
in the detail view — so a backlog of agent guesses is separable from your own
list. The test is the one every other verb already uses: the command ran inside a
herdr pane (`HERDR_PANE_ID`). herdr has no "an agent is typing" marker, so a
person who runs `herdr-kanban add` from a herdr terminal is recorded the same
way; cards you add in the board — the form and the quick-add popup — never claim
an agent filed them. Like the `done` guard below, both of these live on the CLI:
the board's add form never refuses you. An agent-filed card also raises a desktop
notification (`notify_on_add`) — a backlog is where work goes to be forgotten, so
its arrival is worth saying out loud.

**`send`** is the board's `s`, for a script: `herdr-kanban send work-6` dispatches
from anywhere, `herdr-kanban send` dispatches the card for the pane you are in,
and `--dry-run` prints the plan it would run (target column, agent name,
workspace, the flags it would pass, whether it would reuse a running agent)
without touching anything — which is how you check what an automation is about to
do. `--model` and `--workspace` override the card for that one run and are
recorded on it, so a later re-send does not quietly go back to the default;
`--worktree` and `--no-worktree` do the same for the checkout (unset follows the
card). It is
the same `Executor.run` the board uses, prompt-confirmation and all, and the same
bookkeeping: the card records its pane, tab and agent name, and moves to the
column `send_column` picks. The protocol prompt never mentions `send`, so an
agent will not find it by accident; it exists for you and for the automations
plugin ("send the top of the backlog every morning").

All of it writes through the same store, so a board that is already open picks
the change up on its next tick — no server, socket, or callback involved.

**Status rights.** Dispatch moves the card to In Progress, wherever it came from
(see above). An agent may set any column except the board's **Done**, which is
refused by the CLI — both moving a card (`status`) and filing one straight into
it (`add --column`) — the message points at `--force`, and the intention is that
only you close a card. This keeps Done trustworthy and mirrors the convention on
the `tsk` board.

Which column is Done comes from the board, not a literal id: a column with
`role = "done"` (or, on a board without roles, an id in
`done`/`closed`/`complete`/`completed`) is human-only, and every other column is
agent-settable. `show --json` and `list --json` report exactly that set as
`agent_may_set`, and the guard enforces the same set — so the two cannot
disagree, and renaming the Done column does not quietly hand agents the power to
close cards. `block` parks in the column with `role = "blocked"` (falling back
to `blocked`/`waiting`/`on-hold`/`hold`), and the dispatch protocol tells an
agent to run `status <review column>` using `role = "review"`.

The guard is on the CLI only: in the board itself `H`/`L` move a card to any
column, so you are never fighting it. The live reconciliation owns the two
states that are never a judgement call: a card whose agent is working is carried
out of **Queued** (and out of **Blocked**) into In Progress, and a card whose
agent has asked you something is moved into **Blocked** wherever it was — so
Blocked always means the agent is waiting, never just that someone once put the
card there.

**Archiving is yours too.** Taking a card off the board is a decision, not a
step in the work, so `herdr-kanban archive` is refused from inside a herdr pane
unless you pass `--force` — the same rule and the same escape hatch as closing a
card. `unarchive` is unrestricted: putting a card back is always safe. `d` stays
the only way to destroy a card, and it stays a board key; there is no CLI delete.

**Title policy.** The agent's title applies only while the card still carries
its capture title. The moment you rename a card by hand (in the form, or with
`herdr-kanban title cfg-3 "…"` from a shell) the card is yours: a later agent title
is recorded under **Updates** as `suggested title: …` instead of overwriting
you, and `✎` disappears. Only a title you actually typed claims the card: the
edit form sends the title it was opened with only when you changed it, so saving
a priority or a workspace while an agent renames the card in the background
leaves the agent's name alone rather than writing the old one back. The capture
title is kept in `original_title` either way and the detail view shows it, so a
rename is always reversible. Pass `--force` to let an agent override you
deliberately.

`agent_title_overrides = true` in `[behavior]` is that `--force` made standing:
an agent's generated title replaces one you typed, so a card ends up named by
what the work turned out to be rather than by the first thing you wrote. The
title it replaced goes into the card's history as `was: …`, and the CLI answers
`title -> … (by agent, replacing yours)`, so an override is as reversible as any
other rename. This board has it on.

**The tab follows the title.** The tab a dispatch opened is labelled `<card id>
<title>` (`dispatch.tab_label_for`), and every rename — yours in the form or from
a shell, an agent's through the CLI — renames the tab with it, so a card never
shows one name in its column and another in herdr's tab bar. That label is also
how the board recognises its own tab: it compares the live label against the one
it last wrote (`tab_label` on the card), which is why a rename used to make the
board disown the tab it had opened, and why it no longer can.

**Naming a card is the one step agents skip.** It is the only protocol line with
nothing to react to, so a run that is unsure of its wording can send back the
capture title verbatim and tick the box. The board answers that: a rename to the
title the card already has, on a card nobody has retitled, is reported as `still
the capture title "…" — rename it to what the work turned out to be` rather than
a bare `unchanged`, which reads as done. A title the agent itself set — or one
you claimed — still answers `title unchanged`.

**The `blocked` column** is part of the default board (Backlog / Queued / In
Progress / Blocked / Review / Done) precisely so `herdr-kanban block` has
somewhere to put a card. If you drop it from `columns`, `block` still records
the reason as an update and leaves the card where it is, and says so.

## Steps, follow-ups, and why there is no subtask tree

The board has three ways to say "this is bigger than one thing", and none of them
is a nested task:

- **Steps** — a checklist on the card (`herdr-kanban step`), shown as `2/5` on
the meta row and tickable with `1`-`9` in the detail view. This is what an agent
uses to say *how far through* it is, and it is the only progress signal worth
putting on a card.
- **Follow-ups** — a card filed from another card (`add --from`, or implicitly
from the pane), which the detail view shows in both directions. This is what you
use when the work deserves *its own agent*.
- **Labels and workspaces** — for grouping without hierarchy. A label is free
text on a card (`infra`, `docs`), not a badge: it is matched by the `/` filter,
listed by the detail view, carried in `--json`, and read by nothing else, so no
column, ordering, dispatch, `wip_limits` or notification treats a labelled card
any differently. There is no vocabulary for them and no dedupe — the list is
whatever you typed. Comma-separated in the add/edit form, or one `--label <l>`
each on `herdr-kanban add`, which is the CLI's only label flag: changing one
afterwards is the board's edit form, not a verb.

A real subtask tree was considered and left out. The board's unit is a card an
agent runs, and a tree fights that in three places: what column is a parent in
when its children are in three different ones, whose agent updates it, and what
"2/3" means when one child is blocked and one is done. Every one of those is a
whole new state machine in a board whose whole value is that a card's state is one
word you can trust. Steps answer "is this finished", follow-ups answer "who should
do that instead", and neither needs the other's bookkeeping.

If roll-up progress ever becomes the thing you miss, the cheap version is not a
tree: a parent could show `2/3` computed from its children's *columns*, using the
links that already exist. That is a rendering change, not a data model.

**Agent marks** come from herdr-radar's two tables rather than a set of our own,
so a card reads the same as the sidebar row beside it. `ui.icon_mode = "brand"`
(the default) uses the private-use glyphs from its `HerdrAgentIconsMax` font —
logos at `U+E1A0`–`U+E1B7`, and the **lifecycle marks** the font carries too
(`✓` done, `?` blocked, a ring for idle *and* working, which the braille spinner
animates). `icon_mode = "unicode"` uses radar's `TEXT` table verbatim, with one
mark that is deliberately double-width (`✨` for kimi) — every width in the board
is measured in cells, so it costs what it costs. `brand` falls back to `unicode`
by itself when the font is not installed, since a missing glyph is a tofu box.
Both registers are asserted against radar's tables in the plugin's selftest, so
drift is a failed check rather than a card that quietly disagrees with the
sidebar. A kind the font has no mark for (herdr ships `droid`, `letta` and
`muse`, radar's table has none) keeps a plain, unambiguous Unicode mark.

**Which glyphs reach the screen is the terminal's half of the bargain.** The
board emitting `U+E1A9` is necessary but not sufficient: radar's README is
explicit that a fallback *family* is not enough — another font, often a CJK one,
claims that private-use area — so the terminal has to be told to draw the two
ranges from `Herdr Agent Icons Max` by codepoint. Radar's `install-font` action
writes exactly that map into a terminal config it can own; `modules/home/ghostty.nix`
carries the same two `font-codepoint-map` lines because home-manager owns that
file, and a plugin cannot write into the nix store. Without them the board draws
the right codepoints into a terminal that renders something else — which looks
like the board using the wrong marks, and breaks radar's sidebar icons the same
way. iTerm and Windows Terminal have no codepoint map at all; there radar points
at `dist/JetBrainsMonoHerdr-Regular.ttf`, its patched terminal font. `icon_mode =
"unicode"` is the other escape hatch, for a terminal that cannot be told.

The dot in front of a card's workspace label is tinted with that workspace's
colour — the same hues radar's sidebar uses, keyed by herdr's workspace number —
so several workspaces on one board are separable without reading a single label.
The label itself stays neutral, which leaves the agent's mark as the only other
colour on the row. A card whose workspace is closed is the one exception: a red
`⚠` and a red label, because that card's agent has nowhere to run.

**Tasks** live in `~/.local/state/herdr/plugins/herdr-kanban/board.json`
(`$HERDR_PLUGIN_STATE_DIR/board.json` when herdr launches the board): one JSON
document the plugin owns, rewritten atomically under a lock, so a second board
(or a `just switch`) can never clobber it. The standalone `herdr-kanban` CLI
resolves to the same path, so both open the same board. Live cards are the
`tasks` list; a card you archived (`A`) is in the `archived` list beside it,
same shape plus the time and the column it left. It is plain JSON —
hand-editable and diffable, and every write keeps the previous generation beside
it as `board.json.bak` (copied, never renamed, so a reader can never catch the
file mid-swap). If a hand-edit goes wrong, that is the way back. Mutations that
turn out to be no-ops — a status set to the value it already has, an edit with no
effective difference — are not written at all, so they cannot bump the mtime or
rotate that backup away. Parsing is defensive in the other direction too: a field
hand-edited into the wrong type is coerced rather than fatal, so a stray
`"updated_at": "yesterday"` costs you the timestamp, not the board.

**Config** — `modules/home/ai/herdr/plugins/kanban/config.toml`, copied to the
plugin config dir (`~/.config/herdr/plugins/config/herdr-kanban/`) on every
activation, so the repo file is the source of truth:

```toml
[ui]
placement = "overlay"   # overlay = fill the active pane; popup = centred modal
width = "95%"           # popup size only
height = "90%"
quick_add_placement = "popup"   # the capture shortcut's own geometry
quick_add_width = "80%"
quick_add_height = "75%"
animate = true          # spin the indicator on cards whose agent is busy
show_age = true         # show how long each card has been sitting there (>=90s)
show_agent_kind = false # the agent's kind beside its mark on the meta row (π pi)
show_status_word = true # spell out the live state on the card's bottom rule
icon_mode = "brand"     # brand (herdr-radar's font) | unicode (its text marks)

[board]
columns = [ ... ]       # { id, label, role? } in order; ids are what tasks store
                        # `role` names what a column means (`doing`, `blocked`,
                        # `review`, `done`, …) so renaming an id keeps behaviour;
                        # `done` is the human-only column, `doing` is where a
                        # send lands, and a working agent leaves a queued column
default_agent = "pi"
default_column = "backlog"
# wip_limits = { doing = 5 }
stale_after_days = 3    # age is tinted yellow past this, red at 2x; with
                        # show_age = false the id badge carries it instead

[workspaces]
# Short codes for card ids (`cfg-8`). Optional: an unlisted workspace codes by
# its label's slug (`snowflake-reporting` -> `snowfl`, six characters), and a
# code is frozen into the id when a card is filed. Keyed by label, or by
# herdr's workspace id (`w1 = "cfg"`) so a rename cannot change it.
# nixos-config-v2 = "cfg"
# w6 = "snow"

[behavior]
sync_seconds = 2.0             # agent state
workspace_sync_seconds = 10.0  # workspaces, which change far less often
auto_move = false              # true: working -> In Progress, idle/done -> Review
                               # Blocked <-> In Progress follows the agent always
auto_delete_agent = true       # d stops the card's agent too; false keeps it
notify_on_block = true         # a notification the first time an agent blocks on you
notify_on_add = true           # ...and a desktop banner when an agent files a card
notify_system = true           # the desktop half of both; false keeps only the toast
announce_protocol = true  # append the board protocol to every dispatch prompt
agent_title_overrides = true
                        # true: an agent's generated title replaces one you
                        # typed (on the card and its tab); the replaced title is
                        # kept in the card's history. false: your title wins and
                        # an agent's name lands under Updates as a suggestion
worktree = false        # the send form's Git worktree option starts ticked;
                        # a card that owns a checkout always offers it ticked

# Flags handed to an agent the board starts — the same ones you would type after
# `herdr agent start … --`. Without these, a dispatched agent runs with none of
# the flags you use interactively. A card's own model (below) replaces a
# `--model` pair here rather than adding a second one.
[agents.claude]
args = ["--permission-mode=auto"]

# Model names the add/edit form offers per agent kind, passed to the CLI
# verbatim. A kind with no list offers only `default`.
[models]
claude = ["sonnet", "opus", "haiku"]
# pi = ["deepseek-v4-flash", "glm-5.3-flash"]
```

**Deployment** follows the picker's pattern: `home.activation.herdrKanbanPlugin`
copies the manifest and launcher into
`~/.config/herdr/plugins-managed/kanban` and runs `herdr plugin link` there when
the plugin is not registered yet, then reloads the server config to pick up the
`prefix+k` / `ctrl+shift+k` bindings. The board's Python code stays in the
store; `kanban-package.nix` packages it with
`python3.withPackages [ textual ]` and bakes those store paths into the copied
launcher.

The package build **imports every module** with that same interpreter and
asserts each required file is present — including `__main__`, the entry point the
pane actually runs — with `-B` so no bytecode is shipped. It also asserts the
**reverse**: nothing may be packaged that is not on the list, so a new module
cannot slip in unimported. That is deliberate: the board is launched into a pane,
so anything wrong at import time shows up as a board that flashes and closes.
Three ways that bites — a module the flake cannot see because it was never
`git add`-ed, a broken `__main__.py` (which no other module imports), or a stale
launcher pointing at an app build from before a file existed — now fail at build
time, naming the file.

**Working on it** — the same derivation provides a `herdr-kanban` CLI that runs
the board outside herdr and carries the development aids:

```bash
herdr-kanban --snapshot --demo           # the board as plain text, no terminal
herdr-kanban --screen add --width 100 --height 32   # a dialog, via Textual
herdr-kanban --screen board --keys l,enter          # ...after pressing keys
herdr-kanban --selftest                  # headless checks (store, protocol, UI)
herdr-kanban                             # run the board from a plain shell
herdr-kanban --help                      # the task verbs, then these flags
```

`--snapshot` and `--screen` render sample tasks, workspaces, and agents
(`kanban/demo.py`) — including states that are awkward to stage by hand, such as
a blocked agent, a closed workspace, and an agent that exited. A bare
`herdr-kanban` opens the board only when stdout is a terminal; with a pipe (an
agent's captured shell) it prints the verb table instead, because a TUI launched
into a pipe never returns.

`--selftest` also runs as a **pre-commit hook** (`flake-parts/pre-commit.nix`,
scoped to `modules/home/ai/herdr/plugins/kanban/`), so `just check` exercises the
packaged board whenever the plugin changes rather than only when someone
remembers to. It takes about seven seconds and is hermetic: no ambient herdr
environment, no network, no real board file.

A second hook, `scripts/check-kanban-protocol-sync.sh`, compares the protocol
block quoted above with `PROTOCOL_TEMPLATE` itself. It used to be kept in sync by
hand, and it drifted — the `found more work?` line was missing for as long as
nobody compared them — so now a doc that promises an agent something the prompt
does not say fails the commit that changes it.
