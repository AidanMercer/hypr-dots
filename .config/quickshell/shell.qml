import Quickshell
import Quickshell.Io
import "modules/common"
import "modules/bar"
import "modules/launcher"
import "modules/themeswitcher"

ShellRoot {
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    // Single app launcher window; toggled over IPC from the Super keybind.
    Launcher {}

    // Theme switcher overlay; toggled via `qs ipc call themeSwitcher toggle`
    // (Super+Shift+T in hyprland.conf).
    ThemeSwitcher {}

    // Super+M (hyprland.conf) toggles the Arch-logo control popup. The popup
    // lives per-monitor inside each Bar, so rather than reach into a specific
    // window we route through the ControlBus singleton, which opens the popup on
    // whichever monitor currently has focus. One handler, never duplicated.
    IpcHandler {
        target: "controlPopup"
        function toggle(): void { ControlBus.toggleFocused() }
    }
}
