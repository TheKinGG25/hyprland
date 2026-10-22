local programs = require("programs")

local max_volume = 200
local min_bightness = 0

local window = hl.dsp.window
local moveWindow = 30
local resizeWindow = 30

local resizeLeft  = { x = -resizeWindow, y = 0, relative = true }
local resizeRight = { x = resizeWindow,  y = 0, relative = true }
local resizeUp    = { x = 0, y = -resizeWindow, relative = true }
local resizeDown  = { x = 0, y = resizeWindow,  relative = true }

local moveLeft  = { x = -moveWindow, y = 0, relative = true }
local moveRight = { x = moveWindow,  y = 0, relative = true }
local moveUp    = { x = 0, y = -moveWindow, relative = true }
local moveDown  = { x = 0, y = moveWindow,  relative = true }


local function opts(direction)
    return { description = "Resize the active window " .. direction, repeating = true } -- need to make it work for the rest 
end

local function focusAndTeleport(direction)
    return function()
        hl.dispatch(hl.dsp.focus({ direction = direction }))
        hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 1 }))
    end
end

local function workspaceAndTeleport(ws)
    return function()
        hl.dispatch(hl.dsp.focus({ workspace = ws }))
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

hl.bind(mainMod .. " + " .. ctrlMod .. " + left",  window.move({ direction = "left" }),  opts("left"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + right", window.move({ direction = "right" }), opts("right"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + up",    window.move({ direction = "up" }),    opts("up"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + down",  window.move({ direction = "down" }),  opts("down"))

hl.bind(mainMod .. " + " .. ctrlMod .. " + " .. shiftMod .. " + left",  window.move(moveLeft),  opts("left"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + " .. shiftMod .. " + right", window.move(moveRight), opts("right"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + " .. shiftMod .. " + up",    window.move(moveUp),    opts("up"))
hl.bind(mainMod .. " + " .. ctrlMod .. " + " .. shiftMod .. " + down",  window.move(moveDown),  opts("down"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  focusAndTeleport("left"))
hl.bind(mainMod .. " + right", focusAndTeleport("right"))
hl.bind(mainMod .. " + up",    focusAndTeleport("up"))
hl.bind(mainMod .. " + down",  focusAndTeleport("down"))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, workspaceAndTeleport(i))
    hl.bind(mainMod .. " + " .. shiftMod .. " + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

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