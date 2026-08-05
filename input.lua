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
            scroll_factor  = 1,
        },
    },
  
    cursor = {
        no_hardware_cursors = true,
    },
})

-- https://wiki.hypr.land/Configuring/Basics/Gestures/
-- gesture = fingers, direction, action
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- Per-device config: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
hl.device({ name = "epic-mouse-v1",                                  sensitivity = -1    })
hl.device({ name = "asustek-computer-inc.-n-key-device-1",           enabled     = false })
hl.device({ name = "sonix-gaming-keyboard-mouse",                    enabled     = false })
hl.device({ name = "glorious-model-i-2-wireless-consumer-control-1", enabled     = false })
hl.device({ name = "glorious-model-i-2-wireless-consumer-control-3", enabled     = false })
hl.device({ name = "sonix-gaming-keyboard-consumer-control-1",       enabled     = false })
hl.device({ name = "glorious-model-i-2-wireless-mouse-1",            enabled     = false })
