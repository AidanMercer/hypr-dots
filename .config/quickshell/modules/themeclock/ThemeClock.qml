import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"

// Per-monitor desktop clock that belongs to the *active theme*, not to the bar.
//
// Each theme folder (~/.config/themes/<name>/) may drop a clock.qml next to its
// wallpaper. This window asks awww which wallpaper the monitor is currently
// showing, walks up to that theme folder, and loads its clock.qml if present.
// No clock.qml → nothing renders. Swap the wallpaper and the clock swaps with it.
//
// It sits on the Bottom layer (above the wallpaper, below real windows) and is
// fully click-through, so it reads as part of the desktop.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-themeclock"
    WlrLayershell.layer: WlrLayer.Bottom

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}                         // click-through: it's just scenery
    visible: clockPath !== ""

    property string themeDir: ActiveTheme.dirFor(root.modelData ? root.modelData.name : "")
    property string clockPath: ""
    property int reloadNonce: 0

    // Encode each segment so theme names with spaces ("your name") survive.
    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    // ActiveTheme already knows this monitor's theme folder (one shared awww query);
    // we just confirm it ships a clock.qml. Re-runs when the folder changes (theme
    // switch) or a hot-reload is forced.
    Process {
        id: existProc
        stdout: StdioCollector {
            onStreamFinished: root.clockPath = text.trim()
        }
    }
    // Build the lookup command from the CURRENT themeDir at call time, NOT via a
    // declarative `command: [...root.themeDir]` binding. On a theme switch the
    // onThemeDirChanged handler fires BEFORE such a binding re-evaluates, so the
    // process would launch with the PREVIOUS theme's dir and load the wrong widget
    // (the one-behind bug). Reading themeDir at start time always sees the new value.
    function rescan() {
        existProc.command = ["bash", "-c",
            'd="$1"; [ -n "$d" ] && [ -f "$d/clock.qml" ] && printf "%s/clock.qml" "$d"',
            "_", root.themeDir]
        existProc.running = true
    }
    onThemeDirChanged: rescan()

    Loader {
        anchors.fill: parent
        active: root.clockPath !== ""
        source: root.clockPath !== "" ? root.fileUrl(root.clockPath) + "?v=" + root.reloadNonce : ""
    }

    // Hot-reload: watch the loaded file ourselves (quickshell only watches its own
    // config tree, not the theme dirs) and bump the ?v= nonce on save to recompile.
    FileView {
        path: root.clockPath
        watchChanges: root.clockPath !== ""
        printErrors: false
        onFileChanged: root.reloadNonce++
    }

    Component.onCompleted: rescan()

    Connections {
        target: ControlBus
        function onThemeReloadRequested() {
            root.reloadNonce++
            root.rescan()
        }
    }
}
