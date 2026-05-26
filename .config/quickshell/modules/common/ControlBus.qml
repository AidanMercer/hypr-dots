pragma Singleton
import QtQuick
import Quickshell.Hyprland

// Shared open-state for the Arch-logo control popup (the "Arch menu").
//
// The popup is created once *per monitor* (inside each Bar), but only one should
// ever be open at a time and it must be toggleable from a single global keybind
// (Super+M). So instead of each popup owning its own bool, they all read this one
// singleton: it holds the *name* of the monitor whose popup is open ("" = all
// closed). A popup opens only when openMonitor matches its own screen. Both the
// StatusButton click and the Super+M IPC funnel through here, keeping one source
// of truth.
QtObject {
    id: bus

    // Name of the monitor whose popup is currently open, or "" when none is.
    property string openMonitor: ""

    // Toggle the popup on a specific monitor (used by the StatusButton click).
    function toggle(name) {
        openMonitor = (openMonitor === name) ? "" : name
    }

    // Toggle on whichever monitor has focus (used by the Super+M IPC handler).
    function toggleFocused() {
        const m = Hyprland.focusedMonitor
        toggle(m ? m.name : "")
    }

    function close() {
        openMonitor = ""
    }
}
