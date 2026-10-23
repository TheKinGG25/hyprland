local programs = require("programs")
local grid = require("grid")

local max_volume = 200
local min_bightness = 0

local window = hl.dsp.window
local resizeWindow = 30

local resizeLeft  = { x = -resizeWindow, y = 0, relative = true }
local resizeRight = { x = resizeWindow,  y = 0, relative = true }
local resizeUp    = { x = 0, y = -resizeWindow, relative = true }
local resizeDown  = { x = 0, y = resizeWindow,  relative = true }


local function opts(direction)
    return { description = "Resize the active window " .. direction, repeating = true } -- need to make it work for the rest 
end

local function focusAndTeleport(direction)
    return function()
        hl.dispatch(hl.dsp.focus({ direction = direction }))
        hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 1 }))
    end
end

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier
local altMod = "ALT"
local shiftMod = "SHIFT"
local ctrlMod = "CTRL"

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(altMod .. " + Space", hl.dsp.exec_cmd(programs.menu))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(programs.browser))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("pkill quickshell && quickshell"))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + F", window.float({ action = "toggle" }))
hl.bind(mainMod .. " + W", window.close())

hl.bind(mainMod .. " + " .. shiftMod .. " + left",  window.resize(resizeLeft),  opts("left"))
hl.bind(mainMod .. " + " .. shiftMod .. " + right", window.resize(resizeRight), opts("right"))
hl.bind(mainMod .. " + " .. shiftMod .. " + up",    window.resize(resizeUp),    opts("up"))
hl.bind(mainMod .. " + " .. shiftMod .. " + down",  window.resize(resizeDown),  opts("down"))

-- Move the window between tiles; at a monitor's edge it moves to the next monitor (grid.lua)
hl.bind(mainMod .. " + " .. ctrlMod .. " + left",  function() grid.move_dir("left") end,  opts("left"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + right", function() grid.move_dir("right") end, opts("right"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + up",    function() grid.move_dir("up") end,    opts("up"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + down",  function() grid.move_dir("down") end,  opts("down"))

-- Workspace grid (grid.lua): left / right changes n on every monitor, up / down changes m
-- on the focused one. Adding ALT carries the focused window along.
local gridMod = mainMod .. " + " .. ctrlMod .. " + " .. shiftMod
hl.bind(gridMod .. " + left",  function() grid.step_n(-1) end)
hl.bind(gridMod .. " + right", function() grid.step_n(1) end)
hl.bind(gridMod .. " + up",    function() grid.step_m("up") end)
hl.bind(gridMod .. " + down",  function() grid.step_m("down") end)

hl.bind(gridMod .. " + " .. altMod .. " + left",  function() grid.carry_n(-1) end)
hl.bind(gridMod .. " + " .. altMod .. " + right", function() grid.carry_n(1) end)
hl.bind(gridMod .. " + " .. altMod .. " + up",    function() grid.carry_m("up") end)
hl.bind(gridMod .. " + " .. altMod .. " + down",  function() grid.carry_m("down") end)

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  focusAndTeleport("left"))
hl.bind(mainMod .. " + right", focusAndTeleport("right"))
hl.bind(mainMod .. " + up",    focusAndTeleport("up"))
hl.bind(mainMod .. " + down",  focusAndTeleport("down"))

-- Switch every monitor to horizontal workspace n with mainMod + [1-6]
-- Send the active window to n (this monitor's remembered m) with mainMod + SHIFT + [1-6]
for n = 1, 6 do
    hl.bind(mainMod .. " + " .. n, function() grid.switch_n(n) end)
    hl.bind(mainMod .. " + " .. shiftMod .. " + " .. n, function() grid.send_n(n) end)
end

-- Exploded view of the workspace grid (drawn by Quickshell): mainMod + TAB toggles it.
-- While it is open only these keys work, everything else is swallowed (catchall), so neither
-- the focused window nor the other binds see it. Arrows move through the grid: left / right
-- change n on every monitor, up / down move through this monitor's workspaces that have windows.
-- ENTER / ESCAPE / mainMod + TAB close it, CTRL + = / CTRL + - zoom (100% = 3 workspaces across).
hl.bind(mainMod .. " + Tab", function() grid.toggle_overview() end)
hl.define_submap("overview", function()
    hl.bind(mainMod .. " + Tab", function() grid.close_overview() end)
    hl.bind("escape",            function() grid.close_overview() end)
    hl.bind("Return",            function() grid.close_overview() end)
    hl.bind("KP_Enter",          function() grid.close_overview() end)
    hl.bind("left",  function() grid.step_n(-1) end,        { repeating = true })
    hl.bind("right", function() grid.step_n(1) end,         { repeating = true })
    hl.bind("up",    function() grid.browse_m("up") end,    { repeating = true })
    hl.bind("down",  function() grid.browse_m("down") end,  { repeating = true })
    hl.bind(ctrlMod .. " + equal",       function() grid.zoom(1) end,  { repeating = true })
    hl.bind(ctrlMod .. " + minus",       function() grid.zoom(-1) end, { repeating = true })
    hl.bind(ctrlMod .. " + KP_Add",      function() grid.zoom(1) end,  { repeating = true })
    hl.bind(ctrlMod .. " + KP_Subtract", function() grid.zoom(-1) end, { repeating = true })
    hl.bind("catchall", hl.dsp.no_op())
end)

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l " .. max_volume / 100 .. " @DEFAULT_AUDIO_SINK@ 1%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"),                               { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),                              { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),                            { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n" .. min_bightness .. " set 5%+"),                     { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n" .. min_bightness .. " set 5%-"),                     { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))