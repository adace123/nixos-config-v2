-- SPDX-License-Identifier: GPL-2.0-only
--
-- Kiri's engine state and running containers in the OmniShell bar.
--
-- Kiri draws its own menu bar item as an NSStatusItem inside its own process,
-- and macOS has no way to hand that item to another app, so this cannot show
-- Kiri's widget: it draws the same information itself. The `kiri-watcher`
-- launchd agent polls the daemon and pushes runtime values:
--
--   kiri.state       awake | asleep (absent while the daemon is down)
--   kiri.count       running containers
--   kiri.rows        one "name<TAB>image<TAB>status" line per running container
--   kiri.cpus        the VM's CPUs
--   kiri.memory_mib  the VM's memory ceiling
--
-- The agent sends `X-Kiri-Background: 1`, the header Kiri's own window uses for
-- its periodic checks. Kiri leaves those out of its idle timer, so a bar item
-- that refreshes every few seconds does not keep the 8 GB VM awake.

local look = require("../lib/look")
local actions = require("../lib/actions")

-- Kiri's bundle id, as its launch agent and `~/.kiri` both spell it. Kiri has
-- no URL scheme and `kiri ui` only takes `--view`, so a click can open the
-- window but not a single container: the app has to be the target.
local OPEN_KIRI = "notifications open dev.kiri.app"

-- The loopback bridge (`kiri-bridge.py`, run by launchd beside the watcher): a
-- widget cannot run a process or open a unix socket, so stopping a container is
-- POSTed here and the bridge makes the Docker API call on Kiri's own socket.
local BRIDGE = "http://127.0.0.1:47833"

local MARK = "shippingbox.fill"
local DOT = 7

-- The stop button's spinner: a quarter-circle that turns while a stop is in
-- flight, and the frame count that drives it.
local SPINNER = { "◐", "◓", "◑", "◒" }
local FRAME_SECONDS = 0.1
-- A stop that never lands (the watcher stale, the daemon wedged) must not spin
-- for ever: after this many seconds the row goes back and says why.
local STOP_TIMEOUT = 30

local function anyStopping(ctx)
    for _, _ in pairs(ctx.state.stopping or {}) do
        return true
    end
    return false
end

-- Re-arms itself while something is stopping, so the bar redraws and the
-- spinner advances. A timer callback re-renders the widget.
local function animate(ctx)
    if not anyStopping(ctx) then
        return
    end
    omniwm.after(FRAME_SECONDS, function()
        if not anyStopping(ctx) then
            return
        end
        ctx.state.frame = (ctx.state.frame or 0) + 1
        animate(ctx)
    end)
end

local function stop(ctx, name)
    ctx.state.stopping = ctx.state.stopping or {}
    if ctx.state.stopping[name] then
        return
    end
    ctx.state.stopping[name] = true
    ctx.state.stopping_since = ctx.state.stopping_since or {}
    ctx.state.stopping_since[name] = os.time()
    ctx.state.frame = 0
    animate(ctx)
    omniwm.log("kiri", "stop", name)
    omniwm.http({
        url = BRIDGE .. "/stop",
        method = "POST",
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        body = "container=" .. name,
        response = "json",
        timeout = 20,
    }, function(result)
        -- On success the spinner keeps turning: the row is only gone once the
        -- watcher's next poll drops it from `kiri.rows`, which is what
        -- `prune` below waits for.
        if result.ok then
            return
        end
        ctx.state.stopping[name] = nil
        ctx.state.stopping_since[name] = nil
        -- The two failures a user can act on: OmniWM asking for the loopback
        -- approval, and the bridge not running (no `just switch` yet, or its
        -- launchd agent died).
        local detail = tostring(result.json and result.json.error or result.error or result.status)
        if detail == "network_not_approved" then
            detail = "approve 127.0.0.1 for kiri in OmniWM's settings"
        elseif detail == "network_failed" then
            detail = "kiri-bridge is not running"
        end
        ctx.state.error = "Stop failed: " .. detail
        omniwm.after(6, function()
            ctx.state.error = nil
        end)
    end)
end

-- Drops a spinner once the container is gone from the watcher's list (or after
-- the timeout), which is what turns "stopping" into "stopped" visually.
local function prune(ctx, list)
    local stopping = ctx.state.stopping
    if not stopping then
        return
    end
    local present = {}
    for _, container in ipairs(list) do
        present[container.name] = true
    end
    local gone = {}
    local now = os.time()
    for name, since in pairs(ctx.state.stopping_since or {}) do
        if not present[name] then
            gone[#gone + 1] = name
        elseif now - since > STOP_TIMEOUT then
            gone[#gone + 1] = name
            ctx.state.error = "Stop timed out: " .. name
            omniwm.after(6, function()
                ctx.state.error = nil
            end)
        end
    end
    for _, name in ipairs(gone) do
        stopping[name] = nil
        ctx.state.stopping_since[name] = nil
    end
end

function trigger(ctx, event)
    if event.name == "stop" and event.value and event.value ~= "" then
        stop(ctx, event.value)
    end
end

-- `kiri.rows` -> { { name, image, status }, … }, in the order the engine lists
-- them (newest first).
local function containers(ctx)
    local list = {}
    for line in string.gmatch((ctx.data.vars or {})["kiri.rows"] or "", "[^\n]+") do
        local name, image, status = string.match(line, "^(.-)\t(.-)\t(.*)$")
        if name and name ~= "" then
            list[#list + 1] = { name = name, image = image, status = status }
        end
    end
    return list
end

-- 8192 -> "8 GB", 6144 -> "6 GB"; Kiri's resource values are whole MiB.
local function memory(mib)
    local value = tonumber(mib)
    if not value then
        return nil
    end
    local gb = math.floor(value / 1024)
    if value == gb * 1024 then
        return string.format("%d GB", gb)
    end
    return string.format("%.1f GB", value / 1024)
end

-- "2 CPUs · 8 GB", or nil while the VM is down: a sleeping VM has given its
-- memory back, which is the point of Kiri's idle sleep.
local function vmFacts(vars)
    local cpus = vars["kiri.cpus"]
    if not cpus then
        return nil
    end
    local text = string.format("%s CPU%s", cpus, cpus == "1" and "" or "s")
    local size = memory(vars["kiri.memory_mib"])
    if size then
        text = text .. " · " .. size
    end
    return text
end

function render(ctx)
    local vars = ctx.data.vars or {}
    local state = vars["kiri.state"]
    -- No Kiri daemon, no bar item: it appears at login with the daemon.
    if not state then
        return ui.box{ w = 0, h = 0 }
    end

    local scale = look.scale(ctx)
    local count = tonumber(vars["kiri.count"] or "") or 0
    local running = state == "awake"
    local help = "Kiri · "
        .. (running and (count .. (count == 1 and " container" or " containers")) or "asleep")

    -- `center` keeps the glyph and the count in the middle of the capsule:
    -- `look.bar` pads a horizontal item by its edges, and the count is the only
    -- variable-width child.
    local props = { onClick = ui.popout, help = help, gap = 5 * scale, center = true }
    props[#props + 1] = look.glyph{
        name = running and MARK or "shippingbox",
        size = look.px(ctx, "symbol"),
        color = running and "accent" or "mutedForeground",
    }
    if running and count > 0 and ctx.select("settings", "showCount") ~= false then
        props[#props + 1] = look.text{
            text = tostring(count),
            size = 12.5 * scale,
            weight = "medium",
            color = "foreground",
        }
    end
    return look.bar(ctx, props)
end

function popout(ctx)
    local vars = ctx.data.vars or {}
    local state = vars["kiri.state"] or "asleep"
    local running = state == "awake"
    local count = tonumber(vars["kiri.count"] or "") or 0
    local width = look.width
    local margin = width - 24

    -- The hero block: the mark in an accent tile while the VM is up, and the
    -- container count as the headline the bar item abbreviates.
    local mark = ui.stack{
        w = 42,
        h = 42,
        radius = look.radius(21),
        fill = running and "accent/0.16" or "foreground/0.08",
        look.glyph{
            name = running and MARK or "shippingbox",
            size = 20,
            color = running and "accent" or "secondaryForeground",
        },
    }
    local headline
    if running then
        headline = ui.column{ gap = 2, center = false,
            ui.row{ gap = 6, align = "bottom",
                look.text{ text = tostring(count), size = 26, weight = "medium" },
                look.text{
                    text = count == 1 and "container" or "containers",
                    size = 13,
                    color = "secondaryForeground",
                } },
            look.text{
                text = vmFacts(vars) or "Engine running",
                size = 11,
                color = "secondaryForeground",
            } }
    else
        headline = ui.column{ gap = 2, center = false,
            look.text{ text = "Engine asleep", size = 15, weight = "medium" },
            look.text{
                text = "Wakes on the next docker command",
                size = 11,
                color = "secondaryForeground",
            } }
    end

    -- Panel children go in the panel itself, not a nested column: OmniShell
    -- lays out only the first child of a `ui.column` nested in a popout.
    local panel = {
        w = width + 28,
        look.heading("Kiri", width),
        look.group{ w = width, ui.row{ w = margin, gap = 14, mark, headline } },
    }

    local list = containers(ctx)
    prune(ctx, list)
    if #list > 0 then
        local group = { w = width,
            look.text{ text = "Containers", size = 11, weight = "medium", color = "secondaryForeground" } }
        for _, container in ipairs(list) do
            local busy = (ctx.state.stopping or {})[container.name]
            -- The button is the spinner while the stop is in flight; a table
            -- constructor cannot hold a bare if-expression, so pick it here.
            local stopButton
            if busy then
                stopButton = look.text{
                    text = SPINNER[(ctx.state.frame or 0) % #SPINNER + 1],
                    size = 13,
                    weight = "semibold",
                    color = "accent",
                }
            else
                stopButton = look.glyph{ name = "stop.fill", size = 10, color = "foreground" }
            end
            -- The name area opens Kiri; the button at the row's trailing edge
            -- stops the container. They are separate hit areas so a stop cannot
            -- also open the window.
            group[#group + 1] = ui.row{
                w = margin,
                gap = 6,
                pad = 4,
                radius = look.radius(7),
                ui.row{
                    gap = 10,
                    grow = 1,
                    radius = look.radius(6),
                    hover = look.hover,
                    cursor = "pointer",
                    onClick = OPEN_KIRI,
                    help = container.status,
                    ui.box{
                        w = DOT,
                        h = DOT,
                        radius = DOT / 2,
                        fill = busy and "mutedForeground" or "success",
                    },
                    ui.column{ gap = 2, center = false, grow = 1,
                        look.text{
                            text = container.name,
                            size = 13,
                            weight = "medium",
                            maxWidth = margin - 150,
                            lines = 1,
                        },
                        look.text{
                            text = busy and "Stopping…"
                                or (container.status ~= "" and container.status or "running"),
                            size = 11,
                            color = busy and "warning" or "secondaryForeground",
                            maxWidth = margin - 150,
                            lines = 1,
                        } },
                    look.text{
                        text = container.image,
                        style = "mono",
                        size = 11,
                        color = "secondaryForeground",
                        maxWidth = 92,
                        lines = 1,
                    },
                },
                ui.stack{
                    w = 24,
                    h = 24,
                    radius = look.radius(6),
                    fill = "foreground/0.06",
                    hover = look.hover,
                    cursor = "pointer",
                    help = busy and "Stopping…" or ("Stop " .. container.name),
                    -- Click strings run host commands only; the widget's own
                    -- trigger does the POST. While a stop is in flight the
                    -- button is the spinner and takes no clicks.
                    onClick = if busy then nil else "shell trigger kiri stop " .. container.name,
                    stopButton,
                },
            }
        end
        panel[#panel + 1] = look.group(group)
    elseif running then
        panel[#panel + 1] = actions.notice("No containers are running.", width)
    end

    if ctx.state.error then
        panel[#panel + 1] = look.text{
            text = ctx.state.error,
            size = 11,
            color = "error",
            maxWidth = width,
        }
    end

    panel[#panel + 1] = actions.row("arrow.up.forward.app", "Open Kiri", OPEN_KIRI, width)

    return look.panel(ctx, panel)
end
