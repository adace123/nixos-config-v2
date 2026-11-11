-- SPDX-License-Identifier: GPL-2.0-only
--
-- Tailscale account switcher for the OmniShell bar.
--
-- The current login profile is pushed as runtime values by the
-- `tailscale-profiles` launchd agent (`tailscale.label`, `tailscale.state`,
-- `tailscale.profiles`). Switching is the one action a widget cannot run
-- itself — `omniwm.run` has no process launch — so the agent also exposes a
-- loopback HTTP bridge, and a row here POSTs the profile id to it. The agent
-- validates the id against `tailscale switch --list` and runs the switch.
--
-- While the request is in flight the bar item and the chosen row show a
-- quarter-circle spinner; the agent's reply clears it (or shows the failure
-- for a few seconds). The widget declares `127.0.0.1` under
-- `[capabilities] network`; OmniWM approves that host in `shellPermissions`,
-- which the module declares.

local look = require("../lib/look")

local BRIDGE = "http://127.0.0.1:47832"
local SPINNER = { "◐", "◓", "◑", "◒" }
local FRAME_SECONDS = 0.1

local function entries(ctx)
    local list = {}
    for entry in string.gmatch((ctx.data.vars or {})["tailscale.profiles"] or "", "[^;]+") do
        local id, label, current = string.match(entry, "^([^|]+)|([^|]+)|([01])$")
        if id then
            list[#list + 1] = { id = id, label = label, current = current == "1" }
        end
    end
    return list
end

local function frame(ctx)
    return SPINNER[(ctx.state.frame or 0) % #SPINNER + 1]
end

-- A timer callback re-renders the widget, so re-arming itself while a switch
-- is pending is what animates the spinner.
local function spin(ctx)
    if not ctx.state.switching then
        return
    end
    omniwm.after(FRAME_SECONDS, function()
        if not ctx.state.switching then
            return
        end
        ctx.state.frame = (ctx.state.frame or 0) + 1
        spin(ctx)
    end)
end

local function switchProfile(ctx, id)
    if ctx.state.switching then
        return
    end
    ctx.state.switching = id
    ctx.state.frame = 0
    ctx.state.error = nil
    spin(ctx)
    omniwm.log("tailscale", "switch", tostring(id))
    omniwm.http({
        url = BRIDGE .. "/switch",
        method = "POST",
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        body = "id=" .. id,
        response = "json",
        timeout = 30,
    }, function(result)
        ctx.state.switching = nil
        if not result.ok then
            local detail = result.json and result.json.error or result.error or result.status
            ctx.state.error = "Switch failed: " .. tostring(detail)
            omniwm.log("tailscale", "switch failed", result.status, result.error or "")
            omniwm.after(4, function()
                ctx.state.error = nil
            end)
        end
    end)
end

function trigger(ctx, event)
    if event.name == "switch" and event.value and event.value ~= "" then
        switchProfile(ctx, event.value)
    end
end

function render(ctx)
    local scale = look.scale(ctx)
    local vars = ctx.data.vars or {}
    local running = vars["tailscale.state"] == "Running"
    local props = {
        onClick = ui.popout,
        help = "Tailscale",
        gap = 5 * scale,
    }
    if ctx.state.switching then
        props[#props + 1] = look.text{ text = frame(ctx), size = 18 * scale, weight = "semibold", color = "accent" }
    else
        -- The real Tailscale mark, white on transparent; activation copies the
        -- PNG into this widget's folder because OmniShell refuses image paths
        -- that resolve outside it.
        props[#props + 1] = ui.image{ image = "assets/tailscale.png", w = 15 * scale, h = 15 * scale }
    end
    props[#props + 1] = look.text{
        text = vars["tailscale.label"] or "Tailscale",
        size = 13 * scale,
        color = running and "foreground" or "secondaryForeground",
    }
    return look.bar(ctx, props)
end

function popout(ctx)
    local width = look.panelWidth("tailscale")
    local rows = ui.column{ w = width, gap = 2 }
    for _, profile in ipairs(entries(ctx)) do
        local busy = ctx.state.switching == profile.id
        local mark = if busy then
            look.text{ text = frame(ctx), size = 14, color = "accent" }
        else
            look.glyph{ name = profile.current and "checkmark.circle.fill" or "circle", size = 14,
                color = profile.current and "accent" or "secondaryForeground" }
        rows[#rows + 1] = ui.row{
            w = width,
            pad = 8,
            gap = 8,
            radius = look.radius(7),
            hover = look.hover,
            onClick = "shell trigger tailscale switch " .. profile.id,
            mark,
            look.text{ text = profile.label, size = 13, grow = 1 },
        }
    end
    if #rows == 0 then
        rows[#rows + 1] = look.text{ text = "No Tailscale profiles", size = 13, color = "secondaryForeground" }
    end
    if ctx.state.switching then
        rows[#rows + 1] = look.text{ text = "Switching…", size = 12, color = "accent" }
    elseif ctx.state.error then
        rows[#rows + 1] = look.text{ text = ctx.state.error, size = 12, color = "error" }
    end
    rows[#rows + 1] = ui.row{
        w = width,
        pad = 8,
        gap = 8,
        radius = look.radius(7),
        hover = look.hover,
        onClick = "notifications open io.tailscale.ipn.macos",
        look.glyph{ name = "arrow.up.forward.app", size = 14, color = "secondaryForeground" },
        look.text{ text = "Open Tailscale", size = 13, grow = 1 },
    }
    return look.panel(ctx, { w = width, look.heading("Tailscale", width), rows })
end
