# Auto-start Hyprland on tty1 login (paired with getty autologin).
# Guards: only the local tty1 login shell, not SSH, not nested terminals.
if status is-login
    and test -z "$WAYLAND_DISPLAY"
    and test -z "$DISPLAY"
    and test "$XDG_VTNR" = 1
    # tty output silenced for the quiet boot — hyprland keeps its real log
    # in $XDG_RUNTIME_DIR/hypr/<instance>/hyprland.log
    exec Hyprland >/dev/null 2>&1
end
