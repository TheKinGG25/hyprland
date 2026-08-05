-- Odd workspaces on eDP-1, even workspaces on HDMI-A-1
hl.workspace_rule({ workspace = "1",  monitor = "eDP-1"    , default = true})
hl.workspace_rule({ workspace = "2",  monitor = "HDMI-A-1" , default = true})
hl.workspace_rule({ workspace = "3",  monitor = "eDP-1"    })
hl.workspace_rule({ workspace = "4",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "5",  monitor = "eDP-1"    })
hl.workspace_rule({ workspace = "6",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "7",  monitor = "eDP-1"    })
hl.workspace_rule({ workspace = "8",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "9",  monitor = "eDP-1"    })
hl.workspace_rule({ workspace = "10", monitor = "HDMI-A-1" })

-- Switch both monitors simultaneously: mainMod+[1-5] activates paired workspaces
local mainMod = "SUPER"

hl.bind(mainMod .. " + 1", function()
    -- os.execute("hyprctl dispatch workspace 1")
    -- os.execute("hyprctl dispatch workspace 2")
    hl.dsp.focus({workspace = "1"})
    hl.dsp.focus({workspace = "2"})
end)

hl.bind(mainMod .. " + 2", function()
    -- os.execute("hyprctl dispatch workspace 3")
    -- os.execute("hyprctl dispatch workspace 4")
    hl.dsp.focus({workspace = "3"})
    hl.dsp.focus({workspace = "4"})
end)

hl.bind(mainMod .. " + 3", function()
    os.execute("hyprctl dispatch workspace 5")
    os.execute("hyprctl dispatch workspace 6")
end)

hl.bind(mainMod .. " + 4", function()
    os.execute("hyprctl dispatch workspace 7")
    os.execute("hyprctl dispatch workspace 8")
end)

hl.bind(mainMod .. " + 5", function()
    os.execute("hyprctl dispatch workspace 9")
    os.execute("hyprctl dispatch workspace 10")
end)

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
-- hl.bind(mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1  }))
-- hl.bind(mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2  }))
-- hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3  }))
-- hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4  }))
-- hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5  }))
-- hl.bind(mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6  }))
-- hl.bind(mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7  }))
-- hl.bind(mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8  }))
-- hl.bind(mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9  }))
-- hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))
