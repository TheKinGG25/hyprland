-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,
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
