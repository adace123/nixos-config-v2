"""Agent glyphs, workspace badges, and status marks.

Two icon registers, picked by `ui.icon_mode`:

* `brand` — the private-use glyphs from `HerdrAgentIconsMax`, the icon font
  herdr-radar installs. It carries real marks for every agent herdr ships, and
  using them makes the board read the same as the sidebar you already have.
  Fallen back to `unicode` automatically when the font is not installed, since a
  missing glyph renders as a tofu box.
* `unicode` — herdr-radar's `TEXT` table, verbatim: the same agent reads the
  same way in a terminal that cannot reach the icon font. One mark is
  deliberately wide (kimi's `✨`, East Asian Wide), which is why every width in
  this plugin is measured in cells rather than characters.

Both tables — and the lifecycle marks — are copied from herdr-radar's
`lib/logos.js` and `tools/codepoints.toml` rather than invented here: a board
whose marks disagree with the sidebar beside it makes you learn the same agent
twice. `AGENT_KINDS` below is the one table that is ours, because it is herdr's
`agent start --kind` vocabulary in the order the picker should offer it.

Nothing here talks to herdr; `infer_kind` is a best-effort guess used only for
agents the board did not dispatch itself, where the task record is silent.
"""

from __future__ import annotations

import functools
import os
import subprocess
from pathlib import Path

# -- Catppuccin Mocha --------------------------------------------------------

PALETTE = {
    "base": "#1e1e2e",
    "mantle": "#181825",
    "crust": "#11111b",
    "surface0": "#313244",
    "surface1": "#45475a",
    "surface2": "#585b70",
    "overlay0": "#6c7086",
    "overlay1": "#7f849c",
    "overlay2": "#9399b2",
    "subtext0": "#a6adc8",
    "subtext1": "#bac2de",
    "text": "#cdd6f4",
    "blue": "#89b4fa",
    "lavender": "#b4befe",
    "sapphire": "#74c7ec",
    "sky": "#89dceb",
    "teal": "#94e2d5",
    "green": "#a6e3a1",
    "yellow": "#f9e2af",
    "peach": "#fab387",
    "maroon": "#eba0ac",
    "red": "#f38ba8",
    "mauve": "#cba6f7",
    "pink": "#f5c2e7",
    "flamingo": "#f2cdcd",
    "rosewater": "#f5e0dc",
}

# Accent per column, by position, so a custom column list still gets colours.
COLUMN_ACCENTS = (
    PALETTE["overlay1"],
    PALETTE["blue"],
    PALETTE["peach"],
    PALETTE["mauve"],
    PALETTE["green"],
    PALETTE["teal"],
    PALETTE["pink"],
)

# Accent per workspace, keyed by herdr's workspace number so a workspace keeps
# its colour as long as it stays open.
WORKSPACE_ACCENTS = (
    PALETTE["sapphire"],
    PALETTE["green"],
    PALETTE["yellow"],
    PALETTE["mauve"],
    PALETTE["teal"],
    PALETTE["peach"],
    PALETTE["pink"],
    PALETTE["sky"],
)

# -- agent kinds -------------------------------------------------------------

# herdr's `agent start --kind` values, most-used first so the picker opens on
# something sensible.
AGENT_KINDS: tuple[tuple[str, str], ...] = (
    ("pi", "Pi"),
    ("claude", "Claude Code"),
    ("codex", "Codex"),
    ("opencode", "OpenCode"),
    ("gemini", "Gemini CLI"),
    ("cursor", "Cursor Agent"),
    ("hermes", "Hermes"),
    ("copilot", "GitHub Copilot CLI"),
    ("amp", "Amp"),
    ("cline", "Cline"),
    ("devin", "Devin CLI"),
    ("droid", "Droid"),
    ("grok", "Grok CLI"),
    ("kilo", "Kilo Code"),
    ("kimi", "Kimi Code"),
    ("kiro", "Kiro"),
    ("letta", "Letta Code"),
    ("maki", "Maki"),
    ("mastracode", "MastraCode"),
    ("muse", "Muse"),
    ("omp", "OMP"),
    ("agy", "Antigravity CLI"),
    ("qodercli", "Qoder CLI"),
    ("qwen", "Qwen Code"),
)

# Codepoints from herdr-radar's bundled font (`lib/logos.js`, and the
# authoritative `tools/codepoints.toml` it is generated from): contiguous from
# U+E1A0 in the order that plugin maps them. Re-check against codepoints.toml
# before adding a kind here — a wrong codepoint is a tofu box, not an error.
_BRAND_ORDER = (
    "claude",
    "codex",
    "opencode",
    "omp",
    "cline",
    "mastracode",
    "kimi",
    "kilo",
    "maki",
    "pi",
    "hermes",
    "cursor",
    "copilot",
    "deepseek",
    "gemini",
    "gpt",
    "qwen",
    "grok",
    "agy",
    "kiro",
    "amp",
    "devin",
    "qodercli",
    "glm",
)
BRAND_GLYPHS: dict[str, str] = {
    kind: chr(0xE1A0 + index) for index, kind in enumerate(_BRAND_ORDER)
}

# herdr-radar's `TEXT` table (lib/logos.js), in its order. Copied rather than
# curated: the board and the sidebar beside it have to call the same agent the
# same thing, so a mark you dislike here is a change to make upstream, in that
# repo, rather than one to make quietly in this table. `✨` is double-width on
# purpose — the one mark a reader recognises without having learned it — and the
# layout pays for it in cells.
UNICODE_GLYPHS: dict[str, str] = {
    "claude": "§",
    "codex": "Λ",
    "opencode": "◇",
    "omp": "Π",
    "cline": "∇",
    "mastracode": "∑",
    "kimi": "✨",
    "kilo": "♟",
    "maki": "✳",
    "pi": "π",
    "hermes": "☪",
    "cursor": "◆",
    "copilot": "⊙",
    "deepseek": "≋",
    "gemini": "✦",
    "gpt": "✺",
    "qwen": "Ϙ",
    "grok": "✖",
    "agy": "△",
    "kiro": "Ω",
    "amp": "Ʌ",
    "devin": "ꓓ",
    "qodercli": "Ǫ",
    "glm": "Ƶ",
    # herdr ships these kinds, radar's table has no mark for them. Left plain
    # and unambiguous rather than borrowed from a vendor that is not theirs.
    "droid": "⚙",
    "letta": "◈",
    "muse": "✵",
}

# The font carries the lifecycle marks as well (`state_*` in radar's
# codepoints.toml): a check, a question mark, a ring and a hollow circle. They
# live in the font for the same reason the logos do — `✓ ○ ◌` are missing from
# plenty of monospace faces, and a terminal that falls back to a CJK face draws
# them full-width next to text that is not.
#
# `working` shares the ring by design: radar's motion (the braille frames) is
# what says "busy", and the ring is painted in the brand colour. There is no
# mark for `exited` or `pending`, so those two stay Unicode in both registers.
BRAND_STATE_GLYPHS: dict[str, str] = {
    "working": "\ue1c2",
    "done": "\ue1c0",
    "blocked": "\ue1c1",
    "idle": "\ue1c2",
    "unknown": "\ue1c3",
}

FALLBACK_GLYPH = "◆"

# Terminal titles carry the agent's own mark or name; used only for agents the
# board did not dispatch, where there is no task record to ask. Note what is
# *not* in here: the word "pi". It lives inside "pins", "topic" and a dozen
# other words a title might legitimately use, so pi is recognised by its glyph
# and by nothing else — a wrong kind on a card is worse than a missing one.
_TITLE_HINTS: tuple[tuple[str, str], ...] = (
    ("π", "pi"),
    ("claude", "claude"),
    ("codex", "codex"),
    ("opencode", "opencode"),
    ("gemini", "gemini"),
    ("cursor", "cursor"),
    ("hermes", "hermes"),
    ("copilot", "copilot"),
    ("devin", "devin"),
    ("droid", "droid"),
    ("letta", "letta"),
    ("qwen", "qwen"),
    ("kimi", "kimi"),
    ("kiro", "kiro"),
    ("cline", "cline"),
    ("kilo", "kilo"),
    ("maki", "maki"),
    ("muse", "muse"),
    ("grok", "grok"),
    ("amp", "amp"),
    ("omp", "omp"),
    ("agy", "agy"),
    ("qoder", "qodercli"),
    ("mastra", "mastracode"),
)


def kind_label(kind: str) -> str:
    for value, label in AGENT_KINDS:
        if value == kind:
            return label
    return kind or "agent"


@functools.lru_cache(maxsize=1)
def brand_font_installed() -> bool:
    """Is herdr-radar's `HerdrAgentIconsMax` face available to the terminal?"""
    patterns = (
        "~/Library/Fonts",
        "/Library/Fonts",
        "~/Library/Application Support/Fonts",
        "~/.local/share/fonts",
        "~/.fonts",
        "/usr/share/fonts",
        "/usr/local/share/fonts",
    )
    for pattern in patterns:
        root = Path(pattern).expanduser()
        if not root.is_dir():
            continue
        try:
            for path in root.rglob("*HerdrAgentIcons*"):
                if path.is_file():
                    return True
        except OSError:  # pragma: no cover - unreadable font dirs
            continue
    try:
        proc = subprocess.run(
            ["fc-list", ":family=Herdr Agent Icons Max"],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
    except (FileNotFoundError, subprocess.SubprocessError, OSError):
        return False
    return bool(proc.stdout.strip())


def icon_mode(preference: str = "brand") -> str:
    """Resolve the configured mode to the one that will actually render."""
    override = os.environ.get("KANBAN_ICON_MODE")
    if override in ("brand", "unicode"):
        preference = override
    if preference == "brand" and brand_font_installed():
        return "brand"
    return "unicode"


def agent_glyph(kind: str, mode: str = "brand") -> str:
    if mode == "brand":
        return BRAND_GLYPHS.get(kind) or UNICODE_GLYPHS.get(kind) or FALLBACK_GLYPH
    return UNICODE_GLYPHS.get(kind) or FALLBACK_GLYPH


def infer_kind(name: str = "", title: str = "", logo: str = "") -> str:
    """Guess an agent's kind for a live agent the board did not dispatch.

    `logo` is herdr's `harness_logo` token, which radar publishes from whichever
    of its two tables the machine resolved — so both are searched, or a
    text-variant setup would lose every card's kind.
    """
    if logo:
        for table in (BRAND_GLYPHS, UNICODE_GLYPHS):
            for kind, glyph in table.items():
                if logo == glyph or logo.startswith(glyph):
                    return kind
    haystack = f"{title} {name}".lower()
    for hint, kind in _TITLE_HINTS:
        if hint in haystack:
            return kind
    return ""


# -- statuses ----------------------------------------------------------------

# Same vocabulary herdr reports: working, blocked, idle, done, unknown.
STATUS_GLYPHS = {
    "working": "◐",
    "blocked": "▲",
    "done": "✓",
    "idle": "○",
    "unknown": "·",
    "exited": "∅",
    "pending": "◌",
}

STATUS_COLORS = {
    "working": PALETTE["yellow"],
    "blocked": PALETTE["red"],
    "done": PALETTE["green"],
    "idle": PALETTE["overlay2"],
    "unknown": PALETTE["overlay0"],
    "exited": PALETTE["overlay0"],
    "pending": PALETTE["lavender"],
}

# Braille spinner, the same frames herdr-radar animates in the sidebar.
SPINNER_FRAMES = ("⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷")

STATUS_LABELS = {
    "working": "working",
    "blocked": "needs you",
    "done": "done",
    "idle": "idle",
    "unknown": "unknown",
    "exited": "no agent",
    "pending": "starting",
}


def status_glyph(status: str, frame: int = 0, mode: str = "unicode") -> str:
    """The mark for a live status. `frame` animates `working`."""
    if status == "working" and frame:
        return SPINNER_FRAMES[frame % len(SPINNER_FRAMES)]
    if mode == "brand" and status in BRAND_STATE_GLYPHS:
        return BRAND_STATE_GLYPHS[status]
    return STATUS_GLYPHS.get(status, STATUS_GLYPHS["unknown"])


def status_color(status: str) -> str:
    return STATUS_COLORS.get(status, PALETTE["overlay0"])


def status_label(status: str) -> str:
    return STATUS_LABELS.get(status, status)


# -- priorities --------------------------------------------------------------

PRIORITY_GLYPHS = {"urgent": "‼", "high": "▲", "normal": "", "low": "▽"}
PRIORITY_COLORS = {
    "urgent": PALETTE["red"],
    "high": PALETTE["peach"],
    "normal": PALETTE["overlay0"],
    "low": PALETTE["overlay0"],
}


def priority_glyph(priority: str) -> str:
    return PRIORITY_GLYPHS.get(priority, "")


def priority_color(priority: str) -> str:
    return PRIORITY_COLORS.get(priority, PALETTE["overlay0"])


def column_accent(index: int) -> str:
    return COLUMN_ACCENTS[index % len(COLUMN_ACCENTS)]


# Brand-ish colours, herdr-radar's rule set where it has one. Used for the agent
# glyph on a card so a board of mixed agents is scannable at a glance.
AGENT_COLORS: dict[str, str] = {
    "claude": "#d97757",
    "gemini": "#4285f4",
    "kimi": "#1783ff",
    "deepseek": "#4d6bfe",
    "qwen": "#615ced",
    "kiro": "#9046ff",
    "cline": "#586876",
    "kilo": "#9a9808",
    "pi": PALETTE["lavender"],
    "codex": "#10a37f",
    "opencode": PALETTE["teal"],
    "cursor": PALETTE["sky"],
    "copilot": PALETTE["subtext1"],
    "hermes": PALETTE["yellow"],
    "amp": PALETTE["red"],
    "grok": PALETTE["rosewater"],
    "devin": PALETTE["blue"],
    "droid": PALETTE["peach"],
    "letta": PALETTE["mauve"],
    "muse": PALETTE["pink"],
    "maki": PALETTE["green"],
    "omp": PALETTE["sapphire"],
    "agy": PALETTE["maroon"],
    "qodercli": PALETTE["flamingo"],
    "mastracode": PALETTE["teal"],
}


def agent_color(kind: str) -> str:
    return AGENT_COLORS.get(kind, PALETTE["overlay2"])


def workspace_accent(number: int) -> str:
    """The dot's colour on a card: one hue per workspace, keyed by its number.

    Zero means the card's workspace is not in herdr's live list — closed, or
    herdr is unreachable — and gets the same neutral grey the dot has always
    had rather than a colour that would imply a workspace that is still there.
    """
    if number <= 0:
        return PALETTE["overlay2"]
    return WORKSPACE_ACCENTS[(number - 1) % len(WORKSPACE_ACCENTS)]
