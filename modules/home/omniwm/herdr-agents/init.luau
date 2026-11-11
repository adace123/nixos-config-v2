-- SPDX-License-Identifier: MIT
--
-- Herdr agents that need a person, in the OmniShell bar, drawn like Herdr's own
-- agent sidebar: a round status dot, the agent's own mark, its name, and a dim
-- line with its space and tab. Blocked is announced even if the pane is visible
-- somewhere: it is waiting on a person, and the bar is a better place to notice
-- that than a space you are not on.
--
-- Nothing here polls. The `herdr-agents` launchd agent reads herdr-core's
-- terminal list and pushes the rows this list is built from over OmniWM's IPC:
--
--   herdr.counts  one "state=N" pair per status present, for the bar
--   herdr.rows    one "state<TAB>agent<TAB>space / tab" line per agent that is
--                 working, blocked or done, with Herdr's raw agent id for the
--                 mark below
--
-- `omniwmctl shell set` values last until OmniWM quits, which is why the agent
-- re-pushes them every 30 seconds: a relaunched bar would otherwise list
-- nothing until the next agent changed state.

local HERDR_BUNDLE = "dev.herdr.app"

-- Herdr's sidebar marks: a 7 pt round dot per state — no glyphs, no fills. Its
-- theme's roles map onto OmniShell's warning/success/accent. Working gets a dot
-- too rather than the sidebar's spinner: `ui.image` takes raster frames only,
-- and a rotating dot would not read as one.
local DOT = 7
local STATE_COLOR = { blocked = "warning", done = "success", working = "accent" }
local BAR_COLOR = { blocked = "warning", done = "success", working = "accent", idle = "mutedForeground", error = "error" }
local BAR_ORDER = { "blocked", "done", "working", "idle", "error" }
local FACTS_COLOR = "mutedForeground"

-- Clicking a row brings Herdr to the front. Luau cannot run a program, so the
-- pane itself cannot be focused from here (`herdr-app do agent.focus --terminal
-- t…` would need a native provider); opening the app is the host command that
-- gets closest, and Herdr has no URL scheme to deep-link into a pane.
local OPEN_HERDR = "notifications open " .. HERDR_BUNDLE

-- Agent id -> the mark from Herdr's program table (`icons/*.svg` there,
-- rendered to PNG beside this file; see assets/LICENSE-LobeHub.txt). The row's
-- text is the workspace, so the agent is identified by its mark alone.
local AGENTS = {
    ["claude"] = "assets/claude.png",
    ["claude-code"] = "assets/claude.png",
    ["codex"] = "assets/codex.png",
    ["pi"] = "assets/pi.png",
    ["omp"] = "assets/omp.png",
}

-- One popout row is the same width for every agent: status column, mark, and
-- the text column get fixed widths instead of sizing to their contents.
local PANEL_WIDTH = 320
local PANEL_PAD = 8
local ROW_WIDTH = PANEL_WIDTH - 2 * PANEL_PAD
local STATUS_WIDTH = 12
local ICON_SIZE = 16
local ROW_PAD = 3
local ROW_GAP = 8
local TEXT_WIDTH = ROW_WIDTH - 2 * ROW_PAD - STATUS_WIDTH - ICON_SIZE - 2 * ROW_GAP

-- Default's bar metrics, reproduced: a top-level widget cannot import the
-- selected style's `lib/look`, and these are what make it sit like its
-- neighbours at any bar height.
local DEFAULT_BAR = { height = 32, backgrounds = false, transparent = false, vertical = false }

local function bar_style(ctx)
    local bar = ctx.data and ctx.data.bar
    return bar and bar.style or DEFAULT_BAR
end

local function scaled(ctx)
    return bar_style(ctx).height / 32
end

-- The frame around one bar item, matching Default's `look.bar`: a capsule
-- when the bar is transparent with Item Backgrounds on, a soft fill when only
-- Item Backgrounds is on, and nothing otherwise.
local function frame(ctx, props)
    local style = bar_style(ctx)
    local scale = scaled(ctx)
    props.h = style.height - 4
    props.gap = props.gap or 5 * scale
    props.pad = props.pad or 4 * scale
    props.radius = 6 * scale
    if props.onClick then
        props.hover = props.hover or "foreground/0.08"
    end

    if style.transparent and style.backgrounds then
        props.pad = 0
        props.radius = props.h / 2
        props.fill = "surface"
        props.border = "border"
        props.borderWidth = 0.5
        local edge = math.max(0, math.round(props.h * 0.3) - props.gap)
        table.insert(props, 1, ui.box{ w = edge, h = 1 })
        props[#props + 1] = ui.box{ w = edge, h = 1 }
    elseif style.backgrounds then
        props.fill = "foreground/0.06"
    end

    if style.vertical then
        return ui.column(props)
    end
    return ui.row(props)
end

local function dot(ctx, color)
    local size = DOT * scaled(ctx)
    return ui.box{ w = size, h = size, radius = size / 2, fill = color }
end

-- The sidebar's status column: one width whatever the mark, so names line up.
local function status_cell(ctx, color)
    local scale = scaled(ctx)
    return ui.row{ w = STATUS_WIDTH * scale, h = DOT * scale, pad = 0, gap = 0, dot(ctx, color) }
end

local function agent_cell(ctx, agent)
    local scale = scaled(ctx)
    local mark = AGENTS[agent]
    if mark then
        return ui.image{ image = mark, w = ICON_SIZE * scale, h = ICON_SIZE * scale }
    end
    return ui.symbol{ name = "terminal", size = (ICON_SIZE - 1) * scale, color = FACTS_COLOR }
end

-- "blocked=2 done=10 working=1" -> { blocked = 2, done = 10, working = 1 }
local function counts(ctx)
    local tally = {}
    for state, value in string.gmatch((ctx.data.vars or {})["herdr.counts"] or "", "(%a+)=(%d+)") do
        tally[state] = tonumber(value) or 0
    end
    return tally
end

function render(ctx)
    -- Herdr's mark, then how many agents sit in each status that is present.
    local scale = scaled(ctx)
    local tally = counts(ctx)
    local props = {
        key = "herdr-agents",
        gap = 4 * scale,
        onClick = ui.popout,
        cursor = "pointer",
    }
    props[#props + 1] = ui.icon{
        app = HERDR_BUNDLE,
        placeholder = "terminal",
        w = 16 * scale,
        h = 16 * scale,
    }

    for _, state in BAR_ORDER do
        local n = tally[state] or 0
        if n > 0 then
            props[#props + 1] = dot(ctx, BAR_COLOR[state])
            props[#props + 1] = ui.text{
                text = tostring(n),
                size = 12.5 * scale,
                weight = "medium",
                color = BAR_COLOR[state],
                reserve = "00",
            }
        end
    end

    return frame(ctx, props)
end

-- One sidebar group: a dim header and its agent rows, in Herdr's own order —
-- status dot, agent mark, then the workspace the agent runs in.
local function section(ctx, title, state, entries, scale)
    local color = STATE_COLOR[state]
    local rows = {
        gap = 2 * scale,
        pad = 0,
        key = "herdr-section-" .. state,
    }

    -- Herdr's group header: the status dot, the label in that status colour,
    -- then the count in dim text.
    rows[#rows + 1] = ui.row{
        key = "herdr-header-" .. state,
        w = ROW_WIDTH * scale,
        h = 26 * scale,
        -- Same inset as an agent row, so the status dots stack in one column.
        pad = ROW_PAD * scale,
        gap = 6 * scale,
        align = "center",
        status_cell(ctx, color),
        ui.text{ text = title, size = 11.5 * scale, weight = "medium", color = color },
        ui.text{ text = tostring(#entries), size = 11.5 * scale, color = FACTS_COLOR },
    }

    for i, entry in entries do
        local row = {
            key = "herdr-agent-" .. state .. "-" .. i,
            w = ROW_WIDTH * scale,
            h = 26 * scale,
            pad = ROW_PAD * scale,
            gap = ROW_GAP * scale,
            radius = 7 * scale,
            hover = "foreground/0.06",
            cursor = "pointer",
            onClick = OPEN_HERDR,
            help = entry.where,
        }
        row[#row + 1] = status_cell(ctx, color)
        row[#row + 1] = agent_cell(ctx, entry.agent)
        row[#row + 1] = ui.text{
            text = entry.where,
            size = 12.5 * scale,
            color = if state == "done" then FACTS_COLOR else "foreground",
            maxWidth = TEXT_WIDTH * scale,
            lines = 1,
        }
        rows[#rows + 1] = ui.row(row)
    end

    return ui.column(rows)
end

function popout(ctx)
    local showDone = ctx.select("settings", "showDone") ~= false
    local scale = scaled(ctx)

    local lists = { blocked = {}, done = {}, working = {} }
    for line in string.gmatch((ctx.data.vars or {})["herdr.rows"] or "", "[^\n]+") do
        local state, agent, where = string.match(line, "^(%a+)\t([^\t]*)\t(.*)$")
        if lists[state] and (state ~= "done" or showDone) then
            lists[state][#lists[state] + 1] = { agent = agent, where = where }
        end
    end

    local panel = {
        gap = 6 * scale,
        pad = PANEL_PAD * scale,
        w = PANEL_WIDTH * scale,
        radius = 16 * scale,
        material = "glass",
    }

    -- Herdr's own priority order: blocked, done, working.
    local shown = 0
    for _, group in ipairs({
        { "Needs you", "blocked" },
        { "Done", "done" },
        { "Working", "working" },
    }) do
        local entries = lists[group[2]]
        if #entries > 0 then
            shown = shown + #entries
            panel[#panel + 1] = section(ctx, group[1], group[2], entries, scale)
        end
    end
    if shown == 0 then
        panel[#panel + 1] = ui.text{
            text = "No Herdr agent is running or needs you.",
            size = 12 * scale,
            color = FACTS_COLOR,
        }
    end

    return ui.column(panel)
end
