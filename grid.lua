-- #######################################################################################
-- GRID - 2D workspaces, addressed as [n,m] per monitor
--   n = horizontal index 1..6, switched on ALL monitors at once
--   m = vertical index 1.., per monitor, created on demand, kept compact (no gaps)
-- Every monitor has its own vertical stack for every n and remembers its last m per n.
--
-- Hyprland workspace id = monitor_index * 10000 + n * 1000 + m   (eDP-2 = 0, HDMI-A-1 = 1)
--
-- Keybinds (keybinds.lua) and Quickshell call the functions in M. Compaction and monitor
-- hotplug run from hl.on() events. State lives in $XDG_RUNTIME_DIR:
--   hypr-grid.lua   full state, read back after a config reload (reload wipes Lua state)
--   hypr-grid.json  {"n": 1, "screens": {"eDP-2": [m for n=1..6], ...}} for the Quickshell bar
-- Both are reset when Hyprland starts.
-- #######################################################################################

local M = {}

-- ── Tweakables ──
local N_COUNT           = 6
local MAIN              = "eDP-2"      -- always present, takes the external monitor's workspaces
local EXTERNAL          = "HDMI-A-1"   -- hotplugged
local MON_INDEX         = { [MAIN] = 0, [EXTERNAL] = 1 }
local MONITOR_SETTLE_MS = 300          -- wait after a hotplug before renumbering
local ANIM_SPEED        = { workspaces = 1.94, workspacesIn = 1.21, workspacesOut = 1.94 }
local ANIM_CURVE        = "almostLinear"

-- Ids from here up are scratch space (parked empty workspaces, ids in flight), never grid cells
local SCRATCH = 80000

local runtime    = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local STATE_FILE = runtime .. "/hypr-grid.lua"
local VIEW_FILE  = runtime .. "/hypr-grid.json"

-- n:       current horizontal index (global)
-- last_m:  last_m[monitor name][n] = last m that monitor showed for n
-- origin:  origin[n][m] for eDP-2's stack: "e" = its own, a number = came from HDMI-A-1,
--          the number being its m there. Kept in step with every renumbering, so the
--          HDMI-A-1 workspaces are tracked by position and not by id.
-- main_at: eDP-2's {n, m} as of the last normalize, so a reconnect knows where it was
--          even after Hyprland has shuffled workspaces around on its own
-- extra:   monitor index for any monitor not in MON_INDEX
local function fresh_state()
    return { n = 1, last_m = {}, origin = {}, extra = {} }
end

local state = fresh_state()
local busy    = false   -- true while this file is moving workspaces; events wait for it
local hotplug = false   -- true from a monitor (dis)connect until it has been handled

---------------------
---- HELPERS ----
---------------------

local function mon_index(name)
    if MON_INDEX[name] then return MON_INDEX[name] end
    if not state.extra[name] then
        local used = 1
        for _, i in pairs(state.extra) do used = math.max(used, i) end
        state.extra[name] = used + 1
    end
    return state.extra[name]
end

local function encode(mi, n, m)
    return mi * 10000 + n * 1000 + m
end

-- id -> monitor index, n, m; nil when the id is not a grid cell
local function decode(id)
    if type(id) ~= "number" or id < 1000 or id >= SCRATCH then return nil end
    local mi, n, m = id // 10000, (id % 10000) // 1000, id % 1000
    if n < 1 or n > N_COUNT or m < 1 then return nil end
    return mi, n, m
end

local function wrap_n(n)
    return (n - 1) % N_COUNT + 1
end

local function by_m(a, b) return a.m < b.m end

local function change_id(from, to)
    hl.dispatch(hl.dsp.workspace.change_id({ workspace = from, id = to }))
end

local function free_scratch_id()
    local id = SCRATCH
    while hl.get_workspace(id) do id = id + 1 end
    return id
end

-- One monitor's workspaces for n, sorted by m
local function stack(mon_name, n)
    local mi, list = mon_index(mon_name), {}
    for _, ws in ipairs(hl.get_workspaces()) do
        local wmi, wn, wm = decode(ws.id)
        if not ws.special and wmi == mi and wn == n then list[#list + 1] = { m = wm, ws = ws } end
    end
    table.sort(list, by_m)
    return list
end

-- m of the empty slot at the bottom of a stack (an empty top workspace already is that slot)
local function empty_slot(mon_name, n)
    local st = stack(mon_name, n)
    local top = st[#st]
    if not top then return 1 end
    if top.ws.windows == 0 then return top.m end
    return top.m + 1
end

-- The m a monitor lands on when it goes to n
local function remembered(mon_name, n)
    local m = (state.last_m[mon_name] or {})[n] or 1
    return math.min(m, empty_slot(mon_name, n))
end

-- Next m up or down, wrapping through the empty slot. nil = nowhere to go.
local function vertical_target(mon_name, n, m, dir)
    local slot = empty_slot(mon_name, n)
    if slot <= 1 then return nil end   -- the stack is a single empty workspace
    local t
    if dir == "down" then
        t = (m < slot) and m + 1 or 1
    else
        t = (m > 1) and m - 1 or slot - 1
    end
    if t == m then return nil end
    return t
end

local function show(mon_name, id)
    local active = hl.get_active_monitor()
    if not active or active.name ~= mon_name then
        hl.dispatch(hl.dsp.focus({ monitor = mon_name }))
    end
    hl.dispatch(hl.dsp.focus({ workspace = id }))
end

-- n changes slide sideways, m changes slide vertically. Hyprland picks left/right (up/down)
-- by whether the id grows, which matches the grid except when wrapping around.
local anim_style
local function set_anim(style)
    if anim_style == style then return end
    anim_style = style
    for leaf, speed in pairs(ANIM_SPEED) do
        hl.animation({ leaf = leaf, enabled = true, speed = speed, bezier = ANIM_CURVE, style = style })
    end
end

-- Same as the old workspace binds: cursor to the focused window. With no window, put the
-- cursor back where it was, since focusing the other monitor may have warped it there.
local function settle_cursor(cursor)
    if hl.get_active_window() then
        hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 1 }))
    elseif cursor then
        hl.dispatch(hl.dsp.cursor.move({ x = cursor.x, y = cursor.y }))
    end
end

-- A silent move leaves keyboard focus on the window that left. With windows left behind
-- Hyprland focuses one of them; on an emptied workspace, swap in a fresh empty one, which
-- clears focus. Animations are off for the swap so nothing moves on screen.
local function drop_focus(id)
    local ws = hl.get_workspace(id)
    if not ws or ws.windows ~= 0 then return end
    for leaf in pairs(ANIM_SPEED) do hl.animation({ leaf = leaf, enabled = false }) end
    change_id(id, free_scratch_id())
    hl.dispatch(hl.dsp.focus({ workspace = id }))
    anim_style = nil
    set_anim("slide")
end

-- The focused monitor and where it is in the grid (mi is nil off-grid)
local function here()
    local mon = hl.get_active_monitor()
    local ws = mon and mon.active_workspace
    local mi, n, m = decode(ws and ws.id)
    return mon, mi, n, m
end

---------------------
---- STATE FILES ----
---------------------

local function serialize(v)
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do
            local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
            parts[#parts + 1] = key .. "=" .. serialize(x)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

-- atomic: write a temp file, then rename it over the old one
local function write_file(path, text, in_place)
    local tmp = in_place and path or path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return end
    f:write(text)
    f:close()
    if not in_place then os.rename(tmp, path) end
end

local function save()
    write_file(STATE_FILE, "return " .. serialize(state) .. "\n")

    local screens = {}
    for _, mon in ipairs(hl.get_monitors()) do
        local ms = {}
        for n = 1, N_COUNT do ms[n] = tostring(remembered(mon.name, n)) end
        screens[#screens + 1] = string.format("%q:[%s]", mon.name, table.concat(ms, ","))
    end
    -- In place: Quickshell watches this file, and a rename would swap the inode under its watch
    write_file(VIEW_FILE, string.format('{"n":%d,"screens":{%s}}\n', state.n, table.concat(screens, ",")), true)
end

local function load()
    local chunk = loadfile(STATE_FILE, "t", {})
    if not chunk then return end
    local ok, t = pcall(chunk)
    if ok and type(t) == "table" then
        state = fresh_state()
        for k, v in pairs(t) do state[k] = v end
    end
end

---------------------
---- COMPACTION ----
---------------------

-- Bring every workspace back into the grid:
--   * empty workspaces nobody looks at are parked out of the way (Hyprland frees them later)
--   * each stack is renumbered to 1..k with no gaps, last_m and origin shift along
--   * workspaces that ended up on another monitor (HDMI-A-1 unplugged) are appended to that
--     monitor's stack for their n, in order; plain ids made outside the grid are adopted too
-- Safe to call any time: when everything is already in place it changes nothing.
function M.normalize()
    busy = true
    local present = {}
    for _, mon in ipairs(hl.get_monitors()) do present[mon.name] = true end

    local own, adds = {}, {}
    local function bucket(t, mon_name, n)
        t[mon_name] = t[mon_name] or {}
        t[mon_name][n] = t[mon_name][n] or {}
        return t[mon_name][n]
    end

    for _, ws in ipairs(hl.get_workspaces()) do
        local mon = ws.monitor and ws.monitor.name
        if mon and present[mon] and not ws.special and ws.id > 0 and ws.id < SCRATCH then
            local mi, n, m = decode(ws.id)
            if ws.windows == 0 and not ws.visible then
                change_id(ws.id, free_scratch_id())
            elseif mi == mon_index(mon) then
                table.insert(bucket(own, mon, n), { m = m, ws = ws })
            elseif mi then
                local from_external = (mon == MAIN and mi == MON_INDEX[EXTERNAL])
                table.insert(bucket(adds, mon, n), { m = m, ws = ws, tag = from_external and m or "e" })
            else
                local keep_n = ws.windows > 0 and ws.id >= 1 and ws.id <= N_COUNT
                local pn = keep_n and ws.id or state.n
                table.insert(bucket(adds, mon, pn), { m = ws.id, ws = ws, tag = "e" })
            end
        end
    end

    for mon_name in pairs(present) do
        local mi = mon_index(mon_name)
        state.last_m[mon_name] = state.last_m[mon_name] or {}
        local last_m = state.last_m[mon_name]
        for n = 1, N_COUNT do
            local list = (own[mon_name] or {})[n] or {}
            local extra = (adds[mon_name] or {})[n] or {}
            table.sort(list, by_m)
            table.sort(extra, by_m)

            local old_tags = (mon_name == MAIN) and (state.origin[n] or {}) or nil
            local tags = {}
            local last, new_last = last_m[n], nil

            -- Renumbering upward from 1 never hits a used id: entry i only ever moves down
            for i, e in ipairs(list) do
                if e.m ~= i then change_id(e.ws.id, encode(mi, n, i)) end
                if old_tags then tags[i] = old_tags[e.m] or "e" end
                if last and not new_last and e.m >= last then new_last = i end
            end
            local k = #list
            for _, e in ipairs(extra) do
                k = k + 1
                change_id(e.ws.id, encode(mi, n, k))
                if old_tags then tags[k] = e.tag end
            end

            if last then last_m[n] = new_last or (#list + 1) end
            if old_tags then state.origin[n] = tags end
        end
    end

    -- Remember where every monitor is now
    for _, mon in ipairs(hl.get_monitors()) do
        local ws = mon.active_workspace
        local mi, n, m = decode(ws and ws.id)
        if mi then state.last_m[mon.name][n] = m end
        if mi and mon.name == MAIN then state.main_at = { n = n, m = m } end
    end
    local _, mi, n = here()
    if mi then state.n = n end

    save()
    busy = false
end

-- Puts every monitor on n (at its remembered m), keeping focus where it was
local function align_monitors(n, cursor)
    local home = hl.get_active_monitor()
    if not home then return end
    for _, mon in ipairs(hl.get_monitors()) do
        if mon.name ~= home.name then
            show(mon.name, encode(mon_index(mon.name), n, remembered(mon.name, n)))
        end
    end
    show(home.name, encode(mon_index(home.name), n, remembered(home.name, n)))
    settle_cursor(cursor)
end

-- Events arrive in bursts (a close fires close + destroy + workspace.removed), so batch them.
-- If something outside this file changed n (a window asking for focus), the other monitors
-- follow, since n is global.
local pending
local function schedule_sync()
    if pending then return end
    pending = hl.timer(function()
        pending = nil
        if busy or hotplug then return end
        local before = state.n
        M.normalize()
        if state.n ~= before then
            busy = true
            set_anim("slide")
            align_monitors(state.n, hl.get_cursor_pos())
            busy = false
            M.normalize()
        end
    end, { timeout = 50, type = "oneshot" })
end

---------------------
---- ACTIONS ----
---------------------

-- Meta + 1..6: every monitor goes to n, at its own remembered m
function M.switch_n(n)
    if busy or hotplug then return end
    busy = true
    set_anim("slide")
    align_monitors(n, hl.get_cursor_pos())
    state.n = n
    busy = false
    M.normalize()
end

-- Meta + Ctrl + Shift + Left / Right
function M.step_n(delta)
    local _, mi, n = here()
    M.switch_n(wrap_n((mi and n or state.n) + delta))
end

-- Meta + Ctrl + Shift + Up / Down: only the focused monitor moves
function M.step_m(dir)
    if busy or hotplug then return end
    local mon, mi, n, m = here()
    if not mi then return end
    local t = vertical_target(mon.name, n, m, dir)
    if not t then return end
    local cursor = hl.get_cursor_pos()
    set_anim("slidevert")
    hl.dispatch(hl.dsp.focus({ workspace = encode(mi, n, t) }))
    M.normalize()
    settle_cursor(cursor)
end

-- Meta + Shift + 1..6: send the focused window to n at this monitor's remembered m.
-- Focus stays where it is.
function M.send_n(n)
    if busy or hotplug then return end
    local win = hl.get_active_window()
    local mon, mi = here()
    if not win or not mi then return end
    local from = mon.active_workspace.id
    local target = encode(mi, n, remembered(mon.name, n))
    if win.workspace and win.workspace.id == target then return end
    busy = true
    hl.dispatch(hl.dsp.window.move({ workspace = target, follow = false }))
    drop_focus(from)
    busy = false
    M.normalize()
end

-- Meta + Ctrl + Shift + Alt + Left / Right: carry the focused window to the next n and follow it
function M.carry_n(delta)
    if busy or hotplug then return end
    local win = hl.get_active_window()
    local mon, mi, n = here()
    if not win or not mi then return end
    local to = wrap_n(n + delta)
    hl.dispatch(hl.dsp.window.move({ workspace = encode(mi, to, remembered(mon.name, to)), follow = false }))
    M.switch_n(to)
    hl.dispatch(hl.dsp.focus({ window = win }))
    settle_cursor()
end

-- Meta + Ctrl + Shift + Alt + Up / Down: carry the focused window up or down and follow it
function M.carry_m(dir)
    if busy or hotplug then return end
    local win = hl.get_active_window()
    local mon, mi, n, m = here()
    if not win or not mi then return end
    local t = vertical_target(mon.name, n, m, dir)
    if not t then return end
    set_anim("slidevert")
    hl.dispatch(hl.dsp.window.move({ workspace = encode(mi, n, t), follow = true }))
    M.normalize()
    settle_cursor()
end

-- Meta + Ctrl + Arrows: move the window between tiles as usual; at the edge of a monitor it
-- goes to the next monitor over, onto whatever [n,m] that monitor is showing
local DIR_SHORT = { left = "l", right = "r", up = "u", down = "d" }
function M.move_dir(dir)
    if busy or hotplug then return end
    local win = hl.get_active_window()
    if not win then return end
    local ws, x, y = win.workspace and win.workspace.id, win.at.x, win.at.y
    hl.dispatch(hl.dsp.window.move({ direction = dir }))
    local now = hl.get_active_window()
    if now and now.workspace and now.workspace.id == ws and now.at.x == x and now.at.y == y then
        local other = hl.get_monitor(DIR_SHORT[dir])
        local mon = hl.get_active_monitor()
        if other and mon and other.name ~= mon.name then
            hl.dispatch(hl.dsp.window.move({ monitor = DIR_SHORT[dir] }))
            M.normalize()
        end
    end
end

---------------------
---- MONITORS ----
---------------------

-- HDMI-A-1 is back: its workspaces leave eDP-2 in their old order, empty ones are skipped,
-- and it returns to its remembered m for the current n. Hyprland may already have moved
-- some of them over by itself (and put eDP-2 on some other workspace), so each one is looked
-- up by its id, which nothing has changed since the last normalize.
local function reconnect()
    busy = true
    local ext_mi = MON_INDEX[EXTERNAL]
    local function leaves(n, m) return type((state.origin[n] or {})[m]) == "number" end

    -- eDP-2 goes back to where it was, or to the nearest workspace that stays (above first),
    -- or to a new empty one if none stays
    local at = state.main_at or { n = state.n, m = 1 }
    local target = at.m
    if leaves(at.n, at.m) then
        target = nil
        local count = #(state.origin[at.n] or {})
        for d = 1, count do
            for _, c in ipairs({ at.m - d, at.m + d }) do
                if not target and c >= 1 and c <= count and not leaves(at.n, c)
                   and hl.get_workspace(encode(0, at.n, c)) then
                    target = c
                end
            end
            if target then break end
        end
        target = target or 999   -- renumbered by normalize() below
    end
    show(MAIN, encode(0, at.n, target))

    -- Move them over under scratch ids first, so no id collides on the way
    local moved = {}
    for n = 1, N_COUNT do
        local tags = state.origin[n] or {}
        local k, ext_last, new_last = 0, (state.last_m[EXTERNAL] or {})[n], nil
        for m = 1, #tags do
            local ws = hl.get_workspace(encode(0, n, m))
            if leaves(n, m) and ws and ws.windows > 0 then
                local already = ws.monitor and ws.monitor.name == EXTERNAL
                local tmp = free_scratch_id()
                change_id(encode(0, n, m), tmp)
                if not already then
                    hl.dispatch(hl.dsp.workspace.move({ workspace = tmp, monitor = EXTERNAL }))
                end
                k = k + 1
                moved[#moved + 1] = { tmp = tmp, id = encode(ext_mi, n, k) }
                if ext_last and not new_last and tags[m] >= ext_last then new_last = k end
            end
        end
        if ext_last then state.last_m[EXTERNAL][n] = new_last or (k + 1) end
    end
    for _, mv in ipairs(moved) do
        if hl.get_workspace(mv.id) then change_id(mv.id, free_scratch_id()) end
        change_id(mv.tmp, mv.id)
    end

    state.n = at.n
    local cursor = hl.get_cursor_pos()
    show(EXTERNAL, encode(ext_mi, at.n, remembered(EXTERNAL, at.n)))
    hl.dispatch(hl.dsp.focus({ monitor = MAIN }))
    settle_cursor(cursor)
    busy = false
    M.normalize()
end

local settle_timer   -- kept referenced until it fires
local function after_settle(fn)
    settle_timer = hl.timer(fn, { timeout = MONITOR_SETTLE_MS, type = "oneshot" })
end

---------------------
---- EVENTS ----
---------------------

-- New session: forget everything, every monitor starts on [1,1]
hl.on("hyprland.start", function()
    state = fresh_state()
    busy = true
    set_anim("slide")
    for _, mon in ipairs(hl.get_monitors()) do
        if mon.name ~= MAIN then show(mon.name, encode(mon_index(mon.name), 1, 1)) end
    end
    show(MAIN, encode(0, 1, 1))
    busy = false
    M.normalize()
end)

-- HDMI-A-1 unplugged: Hyprland moves its workspaces to eDP-2 by itself, normalize() then
-- renumbers them onto the end of eDP-2's stacks. last_m of HDMI-A-1 is kept for later.
hl.on("monitor.removed", function()
    hotplug = true
    after_settle(function()
        hotplug = false
        M.normalize()
    end)
end)

hl.on("monitor.added", function(mon)
    hotplug = true
    after_settle(function()
        hotplug = false
        if mon and mon.name == EXTERNAL then
            reconnect()
        elseif mon then
            M.normalize()
            busy = true
            local cursor = hl.get_cursor_pos()
            local home = hl.get_active_monitor()
            show(mon.name, encode(mon_index(mon.name), state.n, remembered(mon.name, state.n)))
            if home then hl.dispatch(hl.dsp.focus({ monitor = home.name })) end
            settle_cursor(cursor)
            busy = false
            M.normalize()
        end
    end)
end)

for _, ev in ipairs({ "workspace.removed", "workspace.active", "window.destroy", "window.move_to_workspace" }) do
    hl.on(ev, schedule_sync)
end

-- Config (re)load: pick the state back up, then fix anything that moved meanwhile
load()
set_anim("slide")
M.load_timer = hl.timer(function() if not busy then M.normalize() end end, { timeout = 100, type = "oneshot" })

-- Global, so Quickshell can call grid.switch_n(n) through Hyprland.dispatch / hyprctl eval
grid = M

return M
