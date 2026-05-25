import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules/bar"
import "modules/launcher"
import "modules/common"

ShellRoot {
    id: shell

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    // Single app launcher window; toggled over IPC from the Super keybind.
    Launcher {}

    // ---- "hold Super to reveal workspace numbers" -------------------------
    // Hyprland calls superPressed/superReleased over IPC from the Super
    // press/release keybinds (hyprland.conf). We only reveal after a short
    // hold so a quick Super tap (which opens the launcher) or a Super combo
    // doesn't flash the numbers.
    function clearReveal() {
        revealDelay.stop()
        BarState.showNumbers = false
    }

    // Super held this long (ms) before the numbers appear — long enough to
    // distinguish a deliberate hold from a tap or the start of a combo.
    Timer {
        id: revealDelay
        interval: 180
        onTriggered: BarState.showNumbers = true
    }

    IpcHandler {
        target: "workspaces"
        // Super pressed: arm the reveal (fires only if Super is held past the
        // delay above).
        function superPressed(): void { revealDelay.restart() }
        // Super released: cancel/clear the reveal. Returns whether the numbers
        // were actually showing — the keybind uses this to suppress the
        // launcher toggle after a real hold (vs. a quick tap).
        function superReleased(): bool {
            const wasShowing = BarState.showNumbers
            shell.clearReveal()
            return wasShowing
        }
    }

    // A Super *combo* (Super+T, Super+1, …) is not reported as a clean Super
    // release, so superReleased never fires for it. Each of these events means
    // a combo just ran — clear any pending/active reveal so it can't stick on.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow":
            case "movewindow":
            case "movewindowv2":
            case "workspace":
            case "workspacev2":
                shell.clearReveal()
            }
        }
    }
}
