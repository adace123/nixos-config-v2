---
name: herdr-kanban
description: Work the Herdr kanban board — file, update, and look up cards for agent work. Use when a card id turns up (nixos-64, cfg-8), when a task mentions the board, a card, or herdr-kanban, or when you find work that is separate from the task you were given. Requires running inside a Herdr pane.
---

# Herdr Kanban

`herdr-kanban` is the board of cards for agent work: every card carries the
workspace it belongs to, the agent that should do it, and what that agent is
doing right now. A dispatched agent keeps its own card current through it; any
other agent uses it to file work it found and to read what is already on the
board.

This skill is the judgement layer — which verb to reach for, and what not to
touch. The verbs themselves are the binary's, so read them there rather than
from memory or from an example in a doc:

```bash
herdr-kanban help
```

That prints the verb table and the protocol block a dispatched card is given.

## First: which card is yours?

Cards are found by pane. `HERDR_PANE_ID` links a card to the pane its dispatch
recorded, so inside a dispatched pane a verb with no id means *this* card.

```bash
herdr-kanban list --mine
```

- **It prints a card** — you were dispatched, and the id-less form is yours.
- **`no cards for this pane`** — you were not dispatched through the board, or
  the link was cleared when the agent before you exited. Take the id from your
  prompt (`this card is cfg-8`), or look one up with `herdr-kanban list`, and
  pass it on every verb.

Never guess an id, and never move a card that is not yours.

## Moving the card is how a turn ends

`note` records progress and never moves a card, so a turn that only notes leaves
the card claiming you are still working. Before your final message, decide:

| What is true | What the card should say |
| --- | --- |
| the task is done — including "done, want me to do more?" | move it to the board's review column (the dispatch prompt names it; on this board, `status review`) |
| you cannot continue without the human | `block` with the question they have to answer |
| you are still mid-task | leave it; the board keeps it In Progress |

## Done is the human's to set

`list --json` and `show --json` report `agent_may_set`: every column an agent may
move a card into. Done is never in it. Closing a card is the human's call,
moving work to review is the closest an agent gets, and that is enough — the
refusal names `--force` and says the column is not yours to decide, so do not
reach for the escape hatch to close your own card.

The same holds for `archive`: taking a card off the board is a decision about
the board, not a step in the work.

## Work that is not this task

Found something separate — a bug in another file, a gap in the docs, a follow-up
that needs its own agent? File a card for it instead of doing it here, and
instead of mentioning it in chat where it will be lost:

```bash
herdr-kanban add "<title>" --notes "why it is separate from this one"
```

- Filed from a pane, the card links itself to that pane's card (`found while
  working on cfg-8`), so the reason survives the run that produced it. Outside a
  card's pane, say it yourself with `--from cfg-8`.
- A title the board already has is **refused** and the message names the card
  that covers it — note *that* card instead of filing a second. `--force` is for
  two cards that genuinely share a title, not for getting past the refusal.
- Out of scope is not the same as blocked. You do not need permission to file a
  card; file it and get on with the task you were given.

## Progress, naming, and reading the board

- **Steps** (`herdr-kanban step …`) are the only progress signal worth putting
  on a card — they render as `2/5` on the board, so a long single-card job reads
  at a glance. A part that needs an agent of its own is a separate card, not a
  step.
- **Titles** (`herdr-kanban title …`) — rename the card once the work turns out
  to be something other than its capture title. A title the human typed is
  theirs: unless this board has `agent_title_overrides` on, yours is recorded as
  a suggestion instead of overwriting it.
- **Planning** — `list --json` prints the whole board (bare `list` inside a
  card's pane gives only yours), and `show <id> --json` gives one card in full.
  That is how you check whether a follow-up is already filed, which column
  review really is on this board, and what the human is waiting on. Read
  everything; change only the card you were given and the ones you file.
- **Ids** are `<workspace-code>-<n>` — `cfg-8`, the code naming the workspace the
  card was *filed* in. Matching ignores case and the number alone is unique
  board-wide, so `8` names the same card as `cfg-8`.
- **Nothing to publish.** Each verb writes the board file directly, so a board
  open in a pane (and the board's background reconciler) picks the change up
  on its next tick. There is nothing to poke and no notification to send.

## Not yours to run

- `send` dispatches an agent from a card. It exists for the human and for
  automations; the dispatch protocol never mentions it, and one agent should not
  start another.
- There is no CLI delete. Destroying a card is a board key, and it stays one.
- `archive`, `rename` and the Done column are refused from a pane for the same
  reason as each other: they are the human's call. `--force` exists for the human who
  means it, not for an agent working around a guard.

The full board — keys, columns, config, dispatch behaviour — is written up in
`docs/kanban.md` of the `nixos-config-v2` repo that installs this skill.
