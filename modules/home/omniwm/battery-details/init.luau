-- SPDX-License-Identifier: GPL-2.0-only
--
-- The bundled `battery-details` bar widget with a purple icon. It shadows the
-- Default style's copy (OmniShell looks widgets up in the shell folder before
-- the style folder), so only the bar's cell is redrawn; the state reading and
-- the click-through popout stay on the shared `lib/battery` so charge level,
-- time remaining and the settings row keep working. `lib/` resolves to the
-- style's library folder, which is what makes `require("../lib/…")` work from
-- here exactly as it does in the style's own widget.
--
-- The icon takes the theme's `accent` role instead of `foreground`, which the
-- pinned `omniwm-dark` theme resolves to Catppuccin Mocha mauve (#CBA6F7). The
-- fill keeps the style's warning red/amber, so a low battery still reads as
-- low; charging is purple too, with the bolt marking it.
--
-- The popout also lists the Bluetooth accessories' own batteries, read from
-- `bluetooth.batteries` — one "category<TAB>percent<TAB>name" line per device,
-- pushed by the `bluetooth-battery` launchd agent. OmniWM's own
-- `ctx.data.bluetooth` would carry the same levels but only after a Bluetooth
-- TCC grant, and the agent has to exist anyway for widgets that never ask for
-- that permission. `battery.content` is forked here because the group has to
-- sit above the settings row, and a rendered column cannot be spliced.

local look = require("../lib/look")
local actions = require("../lib/actions")
local battery = require("../lib/battery")
local bluetooth = require("../lib/bluetooth")

local icon = "accent"

-- Accessory Category as IOKit spells it -> the SF Symbol the style's Bluetooth
-- widget uses for the same kind.
local ICONS = {
    Keyboard = "keyboard",
    Mouse = "magicmouse",
    Trackpad = "trackpad",
    Headphones = "headphones",
    Gamepad = "gamecontroller",
    Phone = "iphone",
    Computer = "laptopcomputer",
}

local function tint(state)
    if state.tint == "error" or state.tint == "warning" then
        return state.tint
    end
    return icon
end

-- A copy of `battery.cell` from the style's lib, with the outline, terminal nub
-- and normal-state fill in the icon colour.
local function cell(state, w: number, h: number, inside: string?)
    local body = { w = w, h = h, radius = h * 0.3, border = icon .. "/0.55", borderWidth = 1,
        ui.box{ align = "leading", dx = 2, w = math.max(1.5, (w - 4) * state.level / 100), h = h - 4,
            radius = (h - 4) * 0.3, fill = if inside then tint(state) .. "/0.22" else tint(state) } }
    if inside then
        -- With the percentage inside the cell there is no room for the bolt on
        -- its own, so charging puts a bolt beside the number. Without it the
        -- icon would look identical while charging, because the charging tint
        -- is the same accent as the normal one.
        if state.charging then
            body[#body + 1] = ui.row{ gap = 1,
                look.glyph{ name = "bolt.fill", size = h * 0.52, color = "accentForeground" },
                look.text{ text = inside, size = h * 0.66, weight = "semibold" } }
        else
            body[#body + 1] = look.text{ text = inside, size = h * 0.72, weight = "semibold" }
        end
    elseif state.charging then
        body[#body + 1] = look.glyph{ name = "bolt.fill", size = h * 0.78, color = "accentForeground" }
    end
    return ui.row{ gap = 1,
        ui.stack(body),
        ui.box{ w = math.max(1.5, h * 0.14), h = h * 0.4, radius = h * 0.07, fill = icon .. "/0.55" } }
end

-- `bluetooth.batteries` -> { { category, percent, charging, name }, … },
-- ordered by category then name so the rows do not move as the registry is
-- re-read.
local function accessories(ctx)
    local list = {}
    for line in string.gmatch((ctx.data.vars or {})["bluetooth.batteries"] or "", "[^\n]+") do
        local category, percent, charging, name = string.match(line, "^([^\t]*)\t(%d+)\t([01])\t(.*)$")
        if category and name then
            list[#list + 1] = { category = category, percent = tonumber(percent), charging = charging == "1",
                name = name }
        end
    end
    table.sort(list, function(a, b)
        if a.category ~= b.category then
            return a.category < b.category
        end
        return a.name < b.name
    end)
    return list
end

local function deviceRow(entry, width)
    local row = { w = width - 24, gap = 8, pad = 4,
        ui.stack{ w = 32, h = 32, radius = look.radius(16), fill = "foreground/0.08",
            look.glyph{ name = ICONS[entry.category] or "dot.radiowaves.left.and.right", w = 16, h = 16,
                color = "secondaryForeground" } },
        ui.column{ gap = 3, center = false, grow = 1,
            look.text{ text = entry.name, size = 13, weight = "medium", maxWidth = 150 },
            look.text{ text = entry.category, size = 11, color = "secondaryForeground", maxWidth = 150 } } }
    if entry.charging then
        row[#row + 1] = look.glyph{ name = "bolt.fill", w = 11, h = 11, color = "accent" }
    end
    row[#row + 1] = look.text{ text = entry.percent .. "%", size = 11, color = "secondaryForeground" }
    row[#row + 1] = bluetooth.cell(entry.percent)
    return ui.row(row)
end

local function accessoryGroup(ctx, width)
    local list = accessories(ctx)
    if #list == 0 then
        return nil
    end
    local group = { w = width,
        look.text{ text = "Bluetooth", size = 11, weight = "medium", color = "secondaryForeground" } }
    for _, entry in list do
        group[#group + 1] = deviceRow(entry, width)
    end
    return look.group(group)
end

function render(ctx)
    local state = battery.state(ctx)
    if not state then
        return ui.box{ w = 0, h = 0 }
    end
    local hint = state.percent
    local list = accessories(ctx)
    if #list > 0 then
        local parts = { hint }
        for _, entry in list do
            parts[#parts + 1] = entry.name .. " " .. entry.percent .. "%" ..
                (if entry.charging then " (charging)" else "")
        end
        hint = table.concat(parts, " · ")
    end
    local behaviour = { onClick = ui.popout, help = hint }
    local button = look.batteryDetailsBar and look.batteryDetailsBar(ctx, state)
    if not button then
        local scale = look.scale(ctx)
        local props = table.clone(behaviour)
        if ctx.data.bar.style.vertical then
            props.gap = scale
            props.pad = 2 * scale
            props[#props + 1] = cell(state, 17 * scale, 10 * scale)
            props[#props + 1] = look.text{ text = state.text, size = 10 * scale }
        elseif state.mode == "inside" then
            props[#props + 1] = cell(state, 30 * scale, 15 * scale, state.text)
        else
            props[#props + 1] = cell(state, 23 * scale, 12 * scale)
            if state.mode == "beside" then
                props[#props + 1] = look.text{ text = state.percent, size = 13 * scale, reserve = state.reserve }
            end
        end
        button = look.bar(ctx, props)
    end
    for key, value in behaviour do
        button[key] = value
    end
    return button
end

-- A fork of `battery.content`: the Mac's own charge and details, then the
-- Bluetooth accessories, then the settings row.
local function content(ctx, width: number?, m)
    width = width or look.width
    m = m or battery.model(ctx)
    if not m then
        return actions.notice(omniwm.l10n("Unavailable"), width)
    end
    local rows = { w = width, gap = 12, center = false,
        look.group{ w = width,
            ui.row{ w = width - 24, gap = 16,
                battery.cell(m, 58, 28),
                ui.column{ gap = 3, center = false,
                    look.text{ text = m.percent, size = 28, weight = "medium" },
                    look.text{ text = m.status, size = 13, color = "secondaryForeground", maxWidth = width - 108 } } } } }
    if #m.details > 0 then
        local details = { w = width }
        for _, detail in m.details do
            details[#details + 1] = ui.row{ w = width - 24, gap = 8,
                look.text{ text = detail.label, size = 13, color = "secondaryForeground", grow = 1, maxWidth = 170 },
                look.text{ text = detail.value, size = 13, weight = "medium", maxWidth = 118 } }
        end
        rows[#rows + 1] = look.group(details)
    end
    local devices = accessoryGroup(ctx, width)
    if devices then
        rows[#rows + 1] = devices
    end
    rows[#rows + 1] = actions.row("gearshape", omniwm.l10n("Battery Settings…"), m.settings, width)
    return ui.column(rows)
end

function popout(ctx)
    local m = battery.model(ctx)
    -- A style that supplies its own battery panel keeps it; Default has none.
    return look.batteryPanel and look.batteryPanel(ctx, m)
        or look.panel(ctx, { w = look.width + 28,
            look.heading(omniwm.l10n("Battery"), look.width), content(ctx, nil, m) })
end
