import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"

// Per-monitor desktop lyric visualizer owned by the *active theme*.
//
// Same idea as ThemeClock / ThemeSysInfo: each theme folder
// (~/.config/themes/<name>/) may drop a lyrics.qml next to its wallpaper. This
// window asks awww which wallpaper the monitor is showing, walks up to that
// theme folder, and loads its lyrics.qml if present. No lyrics.qml → nothing
// renders. Swap the wallpaper and it swaps too — so to give a future theme
// lyrics you just drop a lyrics.qml in its folder, nothing here changes.
//
// Bottom layer (above wallpaper, below windows), fully click-through scenery.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-themelyrics"
    WlrLayershell.layer: WlrLayer.Bottom

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    visible: lyricsPath !== ""

    property string themeDir: ActiveTheme.dirFor(root.modelData ? root.modelData.name : "")
    property string lyricsPath: ""
    property int reloadNonce: 0

    // Only ONE instance (the primary screen) should run singletons like the cava
    // silence-detector; the renderer/clock are fine per-screen. lyrics.qml defaults
    // isPrimary=false and we forward the real value onto it once it loads.
    readonly property bool isPrimary:
        Quickshell.screens.length > 0 && root.modelData === Quickshell.screens[0]

    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    // ActiveTheme already knows this monitor's theme folder (one shared awww query);
    // we just confirm it ships a lyrics.qml. Re-runs when the folder changes (theme
    // switch) or a hot-reload is forced.
    Process {
        id: existProc
        command: ["bash", "-c",
            'd="$1"; [ -n "$d" ] && [ -f "$d/lyrics.qml" ] && printf "%s/lyrics.qml" "$d"',
            "_", root.themeDir]
        stdout: StdioCollector {
            onStreamFinished: root.lyricsPath = text.trim()
        }
    }
    onThemeDirChanged: existProc.running = true

    Loader {
        id: lyricsLoader
        anchors.fill: parent
        active: root.lyricsPath !== ""
        source: root.lyricsPath !== "" ? root.fileUrl(root.lyricsPath) + "?v=" + root.reloadNonce : ""
        onLoaded: if (item && item.hasOwnProperty("isPrimary")) item.isPrimary = root.isPrimary
    }

    // Hot-reload: watch the loaded file ourselves (quickshell only watches its own
    // config tree, not the theme dirs) and bump the ?v= nonce on save to recompile.
    FileView {
        path: root.lyricsPath
        watchChanges: root.lyricsPath !== ""
        printErrors: false
        onFileChanged: root.reloadNonce++
    }
    // keep it correct if the screen list reorders after load
    onIsPrimaryChanged: if (lyricsLoader.item && lyricsLoader.item.hasOwnProperty("isPrimary"))
                            lyricsLoader.item.isPrimary = root.isPrimary

    Component.onCompleted: existProc.running = true

    Connections {
        target: ControlBus
        function onThemeReloadRequested() {
            root.reloadNonce++
            existProc.running = true
        }
    }
}
