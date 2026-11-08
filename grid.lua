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
--   hypr-grid.json  read by Quickshell (bar labels and the Meta+Tab overview):
--                   {"n": 1, "overview": {"open": false, "zoom": 3},
--                    "screens": {"eDP-2": {"index": 0, "m": [m per n], "rows": [stack + empty slot per n]}}}
-- Both are reset when Hyprland starts.
--
-- Pinned windows (Meta + P, M.toggle_pin) follow their monitor: when the workspace they are
-- on stops being shown, they move to the one that monitor shows now. Tiled ones are moved with
-- the cursor on their old spot, so the layout splits on that side and they keep their place.
-- Floating ones also get Hyprland's own pin, so they stay put during the slide.
-- They carry the PIN_TAG tag, which the window rule below gives its own border color.
-- #######################################################################################

local M = {}

-- ── Tweakables ──
local N_COUNT           = 6
local MAIN              = "eDP-1"      -- always present, takes the external monitor's workspaces
                                       -- (eDP-1 or eDP-2 depending on the GPU mode, see below)
local EXTERNAL          = "HDMI-A-1"   -- hotplugged

-- The laptop panel hangs off whichever GPU drives it (card1-eDP-1 or card2-eDP-2), so take the
-- one that sysfs reports as connected. Read from /sys because no monitors exist yet at startup.
for card = 0, 3 do
    for _, name in ipairs({ "eDP-1", "eDP-2" }) do
        local f = io.open("/sys/class/drm/card" .. card .. "-" .. name .. "/status")
        if f then
            if f:read("l") == "connected" then MAIN = name end
            f:close()
        end
    end
end

local MON_INDEX         = { [MAIN] = 0, [EXTERNAL] = 1 }
local MONITOR_SETTLE_MS = 300          -- wait after a hotplug before renumbering
local ANIM_SPEED        = { workspaces = 1.94, workspacesIn = 1.21, workspacesOut = 1.94 }
local ANIM_CURVE        = "almostLinear"
local ZOOM_DEFAULT      = 3            -- overview: workspaces visible across (and down) at 100%
local ZOOM_MIN          = 1            -- Ctrl+= stops here (300%)
local ZOOM_MAX          = 6            -- Ctrl+- stops here (50%)
local CURSOR_HIDE_MS    = 150          -- center_cursor: force the cursor invisible this long
local SCROLL_COOLDOWN   = 250         -- scroll_m: ms between steps, so a touchpad swipe or a
                                       -- fast wheel spin moves one workspace at a time
local PIN_TAG           = "pinned"
local PIN_BORDER        = "rgba(ffaa33ee) rgba(b3772480)"   -- pinned windows: active, inactive

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
-- overview: Meta+Tab view drawn by Quickshell; zoom = workspaces visible across
-- pins:    pins[window address] = id of the workspace the pinned window was on at the last
--          normalize. A different id now means it was moved on purpose, so it is not pulled back.
-- pin_spot: pin_spot[window address] = {x, y}, the center of a tiled pinned window as a
--          fraction of its monitor, from the last time it shared a workspace (alone it fills
--          the screen, which says nothing about its side)
local function fresh_state()
    return { n = 1, last_m = {}, origin = {}, extra = {}, pins = {}, pin_spot = {},
             overview = { open = false, zoom = ZOOM_DEFAULT } }
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

-- Cursor to the middle of the focused window. Binds are key presses, so with
-- cursor.hide_on_key_press (input.lua) it stays hidden there until the mouse moves.
-- Also used by the Meta + arrow focus binds in keybinds.lua. Returns false with no window.
-- cursor.invisible is forced on around the warp, so the cursor is not drawn for a frame at its
-- new spot before the key-press hide catches up; after CURSOR_HIDE_MS hide_on_key_press takes over.
local cursor_timer
function M.center_cursor()
    local w = hl.get_active_window()
    if not w or not w.at or not w.size then return false end
    hl.config({ cursor = { invisible = true } })
    hl.dispatch(hl.dsp.cursor.move({ x = math.floor(w.at.x + w.size.x / 2),
                                     y = math.floor(w.at.y + w.size.y / 2) }))
    cursor_timer = hl.timer(function() hl.config({ cursor = { invisible = false } }) end,
                            { timeout = CURSOR_HIDE_MS, type = "oneshot" })
    return true
end

-- Same as the old workspace binds: cursor to the focused window. With no window, put the
-- cursor back where it was, since focusing the other monitor may have warped it there.
local function settle_cursor(cursor)
    if M.center_cursor() then
        return
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
        local ms, rows = {}, {}
        for n = 1, N_COUNT do
            ms[n] = tostring(remembered(mon.name, n))
            rows[n] = tostring(empty_slot(mon.name, n))
        end
        screens[#screens + 1] = string.format('%q:{"index":%d,"m":[%s],"rows":[%s]}', mon.name,
            mon_index(mon.name), table.concat(ms, ","), table.concat(rows, ","))
    end
    local ov = state.overview
    -- In place: Quickshell watches this file, and a rename would swap the inode under its watch
    write_file(VIEW_FILE, string.format('{"n":%d,"overview":{"open":%s,"zoom":%d},"screens":{%s}}\n',
        state.n, tostring(ov.open), ov.zoom, table.concat(screens, ",")), true)
end

local function load()
    local chunk = loadfile(STATE_FILE, "t", {})
    if not chunk then return end
    local ok, t = pcall(chunk)
    if ok and type(t) == "table" then
        state = fresh_state()
        for k, v in pairs(t) do state[k] = v end
    end
    state.pins = state.pins or {}
    state.pin_spot = state.pin_spot or {}
    state.overview.open = false   -- a reload drops the overview submap, so the view closes too
end

---------------------
---- PINS ----
---------------------

local function has_tag(w, tag)
    for _, t in pairs(w.tags or {}) do
        if t == tag then return true end
    end
    return false
end

local function pinned_windows()
    local wins = {}
    for _, w in ipairs(hl.get_windows()) do
        if state.pins[w.address] then wins[w.address] = w end
    end
    return wins
end

-- Pinned windows whose workspace is no longer shown move to what their monitor shows now
local function follow_pins()
    if not next(state.pins) then return end
    local wins = pinned_windows()
    local focus, cursor = hl.get_active_window(), hl.get_cursor_pos()
    local moved = false
    for addr, was in pairs(state.pins) do
        local w = wins[addr]
        local ws = w and w.workspace
        local mon = ws and ws.monitor and hl.get_monitor(ws.monitor.name)
        local to = mon and mon.active_workspace
        if not w then
            state.pins[addr] = nil
            state.pin_spot[addr] = nil
        elseif ws.id == was and not ws.special and not ws.visible and not w.pinned
               and to and to.id ~= ws.id and not to.special then
            local spot = state.pin_spot[addr]
            if not w.floating and spot then
                local s = mon.scale or 1
                hl.dispatch(hl.dsp.cursor.move({ x = math.floor(mon.x + spot[1] * mon.width / s),
                                                 y = math.floor(mon.y + spot[2] * mon.height / s) }))
            end
            hl.dispatch(hl.dsp.window.move({ workspace = to.id, follow = false, window = w }))
            moved = true
        end
    end
    if not moved then return end
    local now = hl.get_active_window()
    if focus and (not now or now.address ~= focus.address) then
        hl.dispatch(hl.dsp.focus({ window = focus }))
    end
    if cursor then hl.dispatch(hl.dsp.cursor.move({ x = cursor.x, y = cursor.y })) end
end

-- After renumbering: remember each pinned window's workspace and spot (see pin_spot), and
-- put the tag back if it went missing (a reload, a rule change)
local function record_pins()
    for addr, w in pairs(pinned_windows()) do
        local ws = w.workspace
        state.pins[addr] = ws and ws.id or 0
        local mon = ws and ws.visible and ws.monitor and hl.get_monitor(ws.monitor.name)
        if mon and not w.floating and ws.windows > 1 and w.at and w.size then
            local s = mon.scale or 1
            state.pin_spot[addr] = { (w.at.x + w.size.x / 2 - mon.x) / (mon.width / s),
                                     (w.at.y + w.size.y / 2 - mon.y) / (mon.height / s) }
        end
        if not has_tag(w, PIN_TAG) then
            hl.dispatch(hl.dsp.window.tag({ tag = "+" .. PIN_TAG, window = w }))
        end
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
    follow_pins()
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

    record_pins()
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
local function show_m(mi, n, t)
    local cursor = hl.get_cursor_pos()
    set_anim("slidevert")
    hl.dispatch(hl.dsp.focus({ workspace = encode(mi, n, t) }))
    M.normalize()
    settle_cursor(cursor)
end

function M.step_m(dir)
    if busy or hotplug then return end
    local mon, mi, n, m = here()
    if not mi then return end
    local t = vertical_target(mon.name, n, m, dir)
    if t then show_m(mi, n, t) end
end

-- Scroll wheel: Meta + Ctrl + Shift + wheel (mon_name nil), or the wheel over the workspace
-- numbers on a Quickshell bar (mon_name = that bar's screen). Same as step_m, at most one step
-- per SCROLL_COOLDOWN. From the bar the cursor goes back where it was, so it stays on the
-- numbers and the next scroll still lands there.
local scroll_lock, scroll_timer = false, nil
function M.scroll_m(dir, mon_name)
    if scroll_lock or busy or hotplug then return end
    if mon_name and not hl.get_monitor(mon_name) then return end
    scroll_lock = true
    scroll_timer = hl.timer(function() scroll_lock = false end, { timeout = SCROLL_COOLDOWN, type = "oneshot" })
    if not mon_name then return M.step_m(dir) end
    local cursor = hl.get_cursor_pos()
    local active = hl.get_active_monitor()
    if not active or active.name ~= mon_name then hl.dispatch(hl.dsp.focus({ monitor = mon_name })) end
    M.step_m(dir)
    if cursor then hl.dispatch(hl.dsp.cursor.move({ x = cursor.x, y = cursor.y })) end
end

-- Up / Down inside the overview: like step_m, but only through workspaces with windows,
-- since the overview does not draw empty ones
function M.browse_m(dir)
    if busy or hotplug then return end
    local mon, mi, n, m = here()
    if not mi then return end
    local last = empty_slot(mon.name, n) - 1   -- the last workspace that has windows
    if last < 1 then return end
    local t
    if m > last then
        t = (dir == "down") and 1 or last
    elseif dir == "down" then
        t = (m < last) and m + 1 or 1
    else
        t = (m > 1) and m - 1 or last
    end
    if t ~= m then show_m(mi, n, t) end
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

-- Meta + P: pin / unpin the focused window (see PINS). Floating windows also get Hyprland's
-- own pin, which keeps them still while the workspace slides.
function M.toggle_pin()
    if busy or hotplug then return end
    local w = hl.get_active_window()
    if not w then return end
    if state.pins[w.address] then
        state.pins[w.address] = nil
        state.pin_spot[w.address] = nil
        hl.dispatch(hl.dsp.window.tag({ tag = "-" .. PIN_TAG, window = w }))
        if w.pinned then hl.dispatch(hl.dsp.window.pin({ window = w })) end
    else
        state.pins[w.address] = w.workspace and w.workspace.id or 0
        hl.dispatch(hl.dsp.window.tag({ tag = "+" .. PIN_TAG, window = w }))
        if w.floating and not w.pinned then hl.dispatch(hl.dsp.window.pin({ window = w })) end
    end
    save()
end

-- Meta + F: float / tile toggle that keeps pins working. Tiling a window that still has
-- Hyprland's own pin crashes Hyprland (assert in the dwindle layout), so that pin is dropped
-- first. A pinned window that gets floated picks up Hyprland's pin instead.
function M.toggle_float()
    local w = hl.get_active_window()
    if not w then return end
    if w.floating and w.pinned then
        hl.dispatch(hl.dsp.window.pin({ window = w }))
        local again = hl.get_active_window()
        if not again or again.address ~= w.address or again.pinned then return end
    end
    local was_floating = w.floating   -- w is live: read it before the toggle changes it
    hl.dispatch(hl.dsp.window.float({ action = "toggle", window = w }))
    if not was_floating and state.pins[w.address] then
        local now = hl.get_active_window()
        if now and now.address == w.address and now.floating and not now.pinned then
            hl.dispatch(hl.dsp.window.pin({ window = now }))
        end
    end
end

hl.window_rule({ name = "grid-pinned-border", match = { tag = PIN_TAG }, border_color = PIN_BORDER })

---------------------
---- OVERVIEW ----
---------------------

-- Meta + Tab: the exploded view. Quickshell draws it from the view file; the "overview" submap
-- (keybinds.lua) holds its keys (arrows, zoom, close) and swallows every other one.
function M.toggle_overview()
    if state.overview.open then return M.close_overview() end
    state.overview.open = true
    hl.dispatch(hl.dsp.submap("overview"))
    save()
end

function M.close_overview()
    state.overview.open = false
    hl.dispatch(hl.dsp.submap("reset"))
    save()
end

-- Ctrl+= (+1) shows fewer, bigger workspaces; Ctrl+- (-1) more, smaller ones
function M.zoom(step)
    local z = state.overview.zoom - step
    state.overview.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
    save()
end

-- A click on [n,m] in a monitor's overview: n changes on every monitor, m on that one
function M.go(mon_name, n, m)
    if busy or hotplug or not hl.get_monitor(mon_name) then return end
    local active = hl.get_active_monitor()
    if not active or active.name ~= mon_name then hl.dispatch(hl.dsp.focus({ monitor = mon_name })) end
    state.last_m[mon_name] = state.last_m[mon_name] or {}
    state.last_m[mon_name][n] = m
    if n ~= state.n then return M.switch_n(n) end
    local cursor = hl.get_cursor_pos()
    set_anim("slidevert")
    hl.dispatch(hl.dsp.focus({ workspace = encode(mon_index(mon_name), n, remembered(mon_name, n)) }))
    M.normalize()
    settle_cursor(cursor)
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
