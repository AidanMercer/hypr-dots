# Auto-start Hyprland on tty1 login (paired with getty autologin).
# Guards: only the local tty1 login shell, not SSH, not nested terminals.
if status is-login
    and test -z "$WAYLAND_DISPLAY"
    and test -z "$DISPLAY"
    and test "$XDG_VTNR" = 1
    # start-hyprland (not raw Hyprland) — registers the session with
    # systemd/dbus and skips the in-session warning banner. tty output
    # silenced for the quiet boot — the real log lands in
    # $XDG_RUNTIME_DIR/hypr/<instance>/hyprland.log
    exec start-hyprland >/dev/null 2>&1
end
