-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
local programs = require("programs")

hl.on("hyprland.start", function()
    -- hl.exec_cmd("quickshell")
    hl.exec_cmd(programs.browser)
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")   -- locks before sleep and on loginctl lock-session, see hypridle.conf
    hl.exec_cmd("vicinae server")
    hl.exec_cmd("/usr/lib/pam_kwallet_init")
	hl.exec_cmd("kwalletd6")
    hl.exec_cmd("sleep 1 && hyprctl dispatch 'hl.dsp.dpms({action = \"off\", monitor = \"eDP-1\"})' && sleep 0.5 && hyprctl dispatch 'hl.dsp.dpms({action = \"on\", monitor = \"eDP-1\"})'")
end)
