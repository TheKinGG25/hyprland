-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    -- hl.exec_cmd("quickshell")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("/usr/lib/pam_kwallet_init")
	hl.exec_cmd("kwalletd6")
    hl.exec_cmd("sleep 1 && hyprctl dispatch dpms off eDP-1 && sleep 0.5 && hyprctl dispatch dpms on eDP-1")
end)
