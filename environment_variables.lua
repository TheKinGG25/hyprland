-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

-- Cursor
hl.env("XCURSOR_THEME",              "Dracula-cursors")
hl.env("XCURSOR_SIZE",               "24")
hl.env("HYPRCURSOR_SIZE",            "24")
hl.env("HYPR_SIZE",                  "24")
hl.env("WLR_NO_HARDWARE_CURSORS",    "1")

-- Rendering / GPU
hl.env("WLR_RENDERER_ALLOW_SOFTWARE","1")
hl.env("LIBVA_DRIVER_NAME",          "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME",  "nvidia")
hl.env("NVD_BACKEND",                "direct")

-- Theming: Qt apps follow the Plasma theme (plasma-integration), also on Hyprland
hl.env("QT_QPA_PLATFORMTHEME",       "kde")
