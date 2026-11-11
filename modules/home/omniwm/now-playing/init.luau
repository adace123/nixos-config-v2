-- SPDX-License-Identifier: GPL-2.0-only
--
-- Now-playing Dynamic Island for OmniShell.
--
-- This source has two placements. On a notchless display it is the root of
-- OmniShell's Dynamic Island (`[island] root` in the active profile): a compact
-- capsule in the bar that drops a player on hover. On the built-in notched
-- display it renders as an ordinary trailing-lane bar widget instead, because
-- the split bar around the notch has no free island lane; clicking that widget
-- opens the bundled media popout. The two placements never show together: the
-- island hides when the display has a notch and the bar widget hides when it
-- does not. Both read the same media feed, and both draw nothing while no track
-- is playing.
--
-- On the island, hovering drops the player out of the capsule: the shape grows
-- down below the bar into artwork, title/artist/album, a scrubber and a
-- transport row. Clicking pins it open; Escape, a press outside or clicking the
-- header collapses it.
--
-- Everything comes from the bundled `media` feed and its actions. `interval = 1`
-- advances the scrubber; the equaliser is a native `loop` paint animation
-- (paused with playback), so it costs no renders of its own. The full model is
-- read rather than per-field selectors because the progress line is part of the
-- compact state too; `media.model(ctx, false, true)` skips the lyrics lookup
-- the bundled popout performs.

local look = require("../lib/look")
local media = require("../lib/media")

local MOTION = { response = 0.36, bounce = 0.14 }
local CONTENT_MOTION = { response = 0.26, bounce = 0.05 }

-- The bar is deployed at 28 pt (`--bar-height 28` in omniwm.nix). The compact
-- capsule is a fully rounded pill inset inside the bar, and the hover player
-- grows down from it. The 2 pt inset is what keeps all four corners of the
-- shape on screen: a shape flush with the display edge loses its top corners.
local BAR_HEIGHT = 28
local INSET = 2
local PILL_HEIGHT = BAR_HEIGHT - 2 * INSET
local HEADER_HEIGHT = 36
local CARD_WIDTH = 400
local BODY_HEIGHT = 166
local CARD_RADIUS = 30

local SURFACE = "#07080c"
local CARD = "#0b0c12"
local FOREGROUND = "#f6f6f7"
local SECONDARY = "#a7a9b2"
local MUTED = "#84868f"

interval = 1

-- Rounded rectangle as a path, so the capsule mask and hairline follow the
-- same shape while the panel grows.
local function outline(width: number, height: number, radius: number): string
    local r = math.min(radius, width / 2, height)
    return string.format(
        "M0 0 H%.2f V%.2f Q%.2f %.2f %.2f %.2f H%.2f Q0 %.2f 0 %.2f Z",
        width,
        height - r,
        width,
        height,
        width - r,
        height,
        r,
        height,
        height - r
    )
end

local function option(ctx, name: string, default: any): any
    local value = ctx.select("settings", name)
    if value == nil then
        return default
    end
    return value
end

local function isExpanded(ctx, settings)
    if ctx.state.pinned then
        return true
    end
    return settings.hoverExpand ~= false and ctx.state.hovered == true
end

local function collapse(ctx)
    ctx.state.pinned = false
    ctx.state.hovered = false
end

local function toggle(ctx, settings)
    if isExpanded(ctx, settings) then
        collapse(ctx)
    else
        ctx.state.pinned = true
    end
end

local function cover(m, size: number, radius: number, action)
    local art
    if m.artwork then
        art = ui.image{ key = "cover:" .. m.title, image = m.artwork, w = size, h = size, radius = radius }
    else
        art = ui.stack{ key = "cover:" .. m.title, w = size, h = size, radius = radius, fill = "#ffffff14",
            ui.symbol{ name = "music.note", size = size * 0.45, color = SECONDARY } }
    end
    if action then
        art.onClick = action
        art.cursor = "pointer"
        art.help = if m.app and m.app ~= "" then m.app else "Now playing"
    end
    art.appear = { opacity = 0, scale = 0.86, animate = CONTENT_MOTION }
    art.exit = { opacity = 0, scale = 0.86, animate = 0.14 }
    return art
end

-- Three bars bobbing on different periods. `paused` holds them still while the
-- track is paused; the unequal heights keep the silhouette from reading as dots.
local function equaliser(playing: boolean, height: number)
    local heights = { height * 0.42, height * 0.86, height * 0.6 }
    local bars = ui.row{ key = "equaliser", h = height, gap = 2 }
    for index, bar_height in heights do
        bars[#bars + 1] = ui.stack{ key = "bar:" .. index, w = 2, h = height, align = "bottom",
            ui.box{
                w = 2,
                h = bar_height,
                radius = 1,
                fill = if playing then "accent" else MUTED,
                animate = CONTENT_MOTION,
                loop = { dy = { 0, bar_height - height, 0.40 + index * 0.08 }, paused = not playing },
            } }
    end
    return bars
end

-- Transport control. The primary play/pause button is filled; the rest are
-- quiet circles that light up with the pointer and an active accent state.
local function button(name: string, size: number, command: string, look)
    look = look or {}
    -- A stack centres its child on both axes; a box would leave the symbol at
    -- the top leading corner.
    return ui.stack{
        w = size,
        h = size,
        radius = size / 2,
        fill = look.fill,
        border = look.border,
        borderWidth = if look.border then 0.5 else nil,
        hover = if look.fill == nil then "foreground/0.10" else nil,
        hoverOpacity = if look.fill then 0.9 else nil,
        hoverScale = if look.fill then 1.05 else 1.04,
        hoverAnimate = "ease",
        pressScale = 0.92,
        pressAnimate = "ease",
        cursor = "pointer",
        onClick = command,
        help = look.help,
        align = "center",
        ui.symbol{
            name = name,
            size = size * (look.icon or 0.42),
            weight = "semibold",
            color = look.tint,
            dx = look.dx,
            dy = look.dy,
        },
    }
end

local function compactWidth(ctx, title: string)
    local titleWidth = ctx.format.measure(title, { size = 12, weight = "semibold" })
    return math.clamp(76 + math.min(titleWidth, 160), 180, 300)
end

-- The island only runs on notchless displays, so its capsule is centred.
local function capsuleCentre(island, width: number)
    local available = math.max(1, island.size.w)
    return math.clamp(available / 2, width / 2, available - width / 2)
end

-- The bar placement gets no notch geometry, so it keys off the display name.
-- The island placement has `island.notch` and hides itself instead; the two
-- checks agree on both displays of this desk (built-in vs external monitor).
local function onBuiltInBar(ctx)
    local bar = ctx.data.bar
    return bar ~= nil
        and bar.style ~= nil
        and type(bar.monitor) == "string"
        and string.find(bar.monitor, "Built%-in") ~= nil
end

local function compactRow(m, width: number)
    local inner = width - 24
    return ui.row{ key = "compact", w = inner, h = PILL_HEIGHT, gap = 8, align = "leading", dx = 12,
        appear = { opacity = 0, scale = 0.96, animate = CONTENT_MOTION },
        exit = { opacity = 0, animate = 0.12 },
        cover(m, 18, 5, nil),
        ui.text{ key = "title:" .. m.title, text = m.title, size = 12, weight = "semibold",
            color = FOREGROUND, maxWidth = inner - 52, lines = 1 },
        ui.box{ grow = 1 },
        equaliser(m.playing, 10) }
end

local function player(m, settings, width: number)
    local inner = width - 32
    local column = ui.column{ w = inner, gap = 2, center = false,
        ui.text{ key = "title:" .. m.title, text = m.title, size = 15, weight = "semibold",
            color = FOREGROUND, maxWidth = inner - 68, lines = 1 },
        if settings.showArtist ~= false
            then ui.text{ key = "artist:" .. m.title,
                text = if m.artist and m.artist ~= "" then m.artist else m.app,
                size = 12, color = SECONDARY, maxWidth = inner - 68, lines = 1 }
            else nil,
        if settings.showAlbum ~= false
            then ui.text{ text = if m.album and m.album ~= "" then m.album else " ", size = 10,
                color = MUTED, maxWidth = inner - 68, lines = 1 }
            else nil }

    local rows = {
        ui.row{ key = "meta", w = inner, gap = 14,
            cover(m, 54, 14, "media open"),
            column },
    }

    if m.fraction then
        rows[#rows + 1] = ui.column{ key = "progress", w = inner, gap = 2,
            ui.slider{ key = "seek", value = m.fraction, w = inner, h = 12, color = "accent", onChange = m.seek },
            ui.row{ key = "times", w = inner,
                ui.text{ text = m.elapsedText or "0:00", size = 10, color = MUTED, reserve = "00:00" },
                ui.box{ grow = 1 },
                ui.text{ text = m.durationText or "", size = 10, color = MUTED, reserve = "00:00" } } }
    end

    local active = if m.playing then "Pause" else "Play"
    local controls = ui.row{ key = "controls", w = inner, h = 34, gap = 8,
        ui.box{ grow = 1 },
        button("shuffle", 24, "media shuffle", {
            tint = if m.shuffle then "accent" else SECONDARY,
            help = "Shuffle",
        }),
        button("backward.fill", 28, "media previous", {
            fill = "foreground/0.06",
            tint = FOREGROUND,
            icon = 0.4,
            help = "Previous",
        }),
        button(m.playSymbol, 34, "media toggle", {
            fill = "accent",
            tint = "accentForeground",
            icon = 0.4,
            help = active,
        }),
        button("forward.fill", 28, "media next", {
            fill = "foreground/0.06",
            tint = FOREGROUND,
            icon = 0.4,
            help = "Next",
        }),
        button(if m.repeatMode == "one" then "repeat.1" else "repeat", 24, "media repeat", {
            tint = if m.repeating then "accent" else SECONDARY,
            help = "Repeat",
        }),
        ui.box{ grow = 1 },
    }
    rows[#rows + 1] = controls

    local body = {
        key = "body",
        w = width,
        h = BODY_HEIGHT,
        pad = 16,
        gap = 8,
        center = false,
        align = "top",
        dy = HEADER_HEIGHT,
        appear = { opacity = 0, dy = -8, animate = CONTENT_MOTION },
        exit = { opacity = 0, dy = -8, animate = { response = 0.18, bounce = 0 } },
    }
    for _, row in rows do
        body[#body + 1] = row
    end
    return ui.column(body)
end

-- Ordinary trailing-lane widget for the built-in display.
local function barItem(ctx, m)
    local scale = look.scale(ctx)
    local props = {
        onClick = ui.popout,
        onRightClick = "media toggle",
        help = if m.artist and m.artist ~= "" then m.title .. " — " .. m.artist else m.title,
        gap = 5 * scale,
    }
    props[1] = cover(m, 18 * scale, 5 * scale, nil)
    props[#props + 1] = look.text{ text = m.title, size = 12 * scale, maxWidth = 170 * scale }
    props[#props + 1] = equaliser(m.playing, math.max(8, 10 * scale))
    return look.bar(ctx, props)
end

function popout(ctx)
    local m = media.model(ctx, false, true)
    if not m then
        return look.text{ text = "Nothing is playing", pad = 12 }
    end
    return look.panel(ctx, { w = look.width + 28, look.heading(omniwm.l10n("Media")),
        media.content(ctx, false, nil, m) })
end

function render(ctx)
    local island = ctx.data.island
    if not island then
        -- Bar placement: the built-in display only.
        if not onBuiltInBar(ctx) then
            return ui.box{ w = 0, h = 0 }
        end
        local m = media.model(ctx, false, true)
        if not m then
            return ui.box{ w = 0, h = 0 }
        end
        return barItem(ctx, m)
    end

    -- Island placement: the notched display uses the bar widget instead.
    local notch = island.notch
    if notch and (notch.w or 0) > 0 and (notch.h or 0) > 0 then
        return ui.box{ w = 0, h = 0 }
    end

    local m = media.model(ctx, false, true)
    if not m then
        return ui.box{ w = 0, h = 0 }
    end
    local settings = {
        hoverExpand = option(ctx, "hoverExpand", true),
        showArtist = option(ctx, "showArtist", true),
        showAlbum = option(ctx, "showAlbum", true),
    }
    local expanded = isExpanded(ctx, settings)

    local availableWidth = math.max(1, island.size.w)
    local availableHeight = math.max(1, island.size.h)
    local top = math.max(0, (island.menuBar or BAR_HEIGHT) - BAR_HEIGHT - 1) + INSET

    local compactW = math.min(availableWidth, compactWidth(ctx, m.title))
    local width = compactW
    local height = PILL_HEIGHT
    local radius = PILL_HEIGHT / 2
    if expanded then
        width = math.min(availableWidth, math.max(CARD_WIDTH, compactW))
        height = HEADER_HEIGHT + BODY_HEIGHT
        radius = CARD_RADIUS
    end
    local centre = capsuleCentre(island, width)

    local panel = {
        key = "island",
        w = width,
        h = height,
        align = "top",
        dx = centre - availableWidth / 2,
        dy = top,
        fill = if expanded then CARD else SURFACE,
        shadow = if expanded then "#00000080" else nil,
        shadowRadius = if expanded then 24 else nil,
        animate = MOTION,
        appear = { opacity = 0, scale = 0.92, animate = CONTENT_MOTION },
        exit = { opacity = 0, scale = 0.92, animate = { response = 0.18, bounce = 0 } },
        hoverDelay = 0.2,
        hoverGrace = 0.24,
        cursor = "pointer",
        focusable = true,
        focusRing = false,
        keys = if expanded then { "escape" } else {},
        onKey = if expanded then collapse else nil,
        onHover = function(next, event)
            next.state.hovered = event.phase == "began"
        end,
        onOutsidePress = if expanded then collapse else nil,
        -- The path masks the whole stack, so the card tint, the surface and the
        -- hairline all share the island's outline as it grows.
        ui.path{
            key = "shape",
            w = width,
            h = height,
            viewBox = { 0, 0, width, height },
            mask = true,
            d = outline(width, height, radius),
            animate = MOTION,
        },
    }

    if expanded then
        panel[#panel + 1] = ui.text{
            key = "caption",
            text = "NOW PLAYING",
            size = 9,
            weight = "semibold",
            color = MUTED,
            align = "top",
            dy = 13,
        }
        panel[#panel + 1] = ui.box{
            key = "divider",
            w = width - 32,
            h = 1,
            align = "top",
            dy = HEADER_HEIGHT - 1,
            fill = "foreground/0.07",
        }
        panel[#panel + 1] = player(m, settings, width)
    else
        panel[#panel + 1] = compactRow(m, width)
    end

    -- Header hit target: the compact capsule, and the empty strip above the
    -- card when open. The card's own controls sit below it and keep their clicks.
    panel[#panel + 1] = ui.box{
        key = "header-hit",
        w = width,
        h = if expanded then HEADER_HEIGHT else PILL_HEIGHT,
        align = "top",
        cursor = "pointer",
        onClick = function(next)
            toggle(next, settings)
        end,
        onRightClick = "media toggle",
    }

    panel[#panel + 1] = ui.path{
        key = "edge",
        w = width,
        h = height,
        viewBox = { 0, 0, width, height },
        d = outline(width, height, radius),
        border = if expanded then "accent/0.40" else "foreground/0.14",
        borderWidth = 0.5,
        animate = MOTION,
        decorative = true,
    }

    return ui.stack{ w = availableWidth, h = availableHeight, ui.stack(panel) }
end
