pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Global on/off for the workspace overview (Super+Shift+/ → Settings). Its own
// singleton rather than a ThemeSettings slot because the exposé is shell-wide,
// not per-theme. Two readers: the settings row, and the overlay itself — which
// refuses to open while it's off. No file yet = on, same as the theme slots.
QtObject {
    id: ovs

    property bool enabled: true

    function setEnabled(v) {
        ovs.enabled = v
        stateFile.setText(v ? "1\n" : "0\n")
    }
    function toggle() { ovs.setEnabled(!ovs.enabled) }

    property FileView _file: FileView {
        id: stateFile
        path: Quickshell.stateDir + "/workspace-overview"
        blockLoading: true
        preload: true
        printErrors: false
    }

    Component.onCompleted: {
        const t = stateFile.text().trim()
        if (t !== "") ovs.enabled = t === "1"
    }
}
