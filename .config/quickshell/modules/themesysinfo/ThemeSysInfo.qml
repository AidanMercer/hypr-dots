import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"

// Per-monitor desktop system-info widget owned by the *active theme*.
//
// Same idea as ThemeClock: each theme folder (~/.config/themes/<name>/) may drop
// a sysinfo.qml next to its wallpaper. This window asks awww which wallpaper the
// monitor is showing, walks up to that theme folder, and loads its sysinfo.qml if
// present. No sysinfo.qml → nothing renders. Swap the wallpaper and it swaps too.
//
// Bottom layer (above wallpaper, below windows), fully click-through scenery.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-themesysinfo"
    WlrLayershell.layer: WlrLayer.Bottom

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    visible: infoPath !== ""

    property string themeDir: ActiveTheme.dirFor(root.modelData ? root.modelData.name : "")
    property string infoPath: ""
    property int reloadNonce: 0

    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    // ActiveTheme already knows this monitor's theme folder (one shared awww query);
    // we just confirm it ships a sysinfo.qml. Re-runs when the folder changes (theme
    // switch) or a hot-reload is forced.
    Process {
        id: existProc
        command: ["bash", "-c",
            'd="$1"; [ -n "$d" ] && [ -f "$d/sysinfo.qml" ] && printf "%s/sysinfo.qml" "$d"',
            "_", root.themeDir]
        stdout: StdioCollector {
            onStreamFinished: root.infoPath = text.trim()
        }
    }
    onThemeDirChanged: existProc.running = true

    Loader {
        anchors.fill: parent
        active: root.infoPath !== ""
        source: root.infoPath !== "" ? root.fileUrl(root.infoPath) + "?v=" + root.reloadNonce : ""
    }

    // Hot-reload: watch the loaded file ourselves (quickshell only watches its own
    // config tree, not the theme dirs) and bump the ?v= nonce on save to recompile.
    FileView {
        path: root.infoPath
        watchChanges: root.infoPath !== ""
        printErrors: false
        onFileChanged: root.reloadNonce++
    }

    Component.onCompleted: existProc.running = true

    Connections {
        target: ControlBus
        function onThemeReloadRequested() {
            root.reloadNonce++
            existProc.running = true
        }
    }
}
