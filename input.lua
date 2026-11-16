-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "fkeys:plain", -- F13-F24 as plain F keys, see ~/.config/xkb
        kb_rules   = "",

        follow_mouse = 1,
        -- Only refocus on hover when the cursor enters a different window. With the default (true),
        -- Hyprland re-sends focus to the window under a resting cursor whenever it simulates a mouse
        -- move, which includes the moment a layer like the Vicinae launcher maps. Since center_cursor
        -- (grid.lua) parks the cursor on the focused window, that stole focus from the launcher.
        mouse_refocus = false,
        sensitivity  = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
            scroll_factor  = 0.5,
        },
    },
  
    cursor = {
        no_hardware_cursors = true,
        hide_on_key_press   = true,   -- hidden from any key press until the mouse moves, so the
                                      -- warp to a newly focused window's middle stays invisible
    },
})

-- https://wiki.hypr.land/Configuring/Basics/Gestures/
-- gesture = fingers, direction, action
-- hl.gesture({
--     fingers   = 3,
--     direction = "horizontal",
--     action    = "workspace",
-- })

-- Per-device config: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
-- hl.device({ name = "epichy-mouse-v1",                     sensitivity = -1   })
-- hl.device({ name = "glorious-model-i-2-wireless-mouse",	  sensitivity = -0.5 })
-- hl.device({ name = "glorious-model-i-2-wireless-mouse-1", sensitivity = -0.5 })
