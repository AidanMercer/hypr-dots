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

    property string lyricsPath: ""
    property int retriesLeft: 10
    property int reloadNonce: 0

    // Only ONE instance (the primary screen) should run singletons like the cava
    // silence-detector; the renderer/clock are fine per-screen. lyrics.qml defaults
    // isPrimary=false and we forward the real value onto it once it loads.
    readonly property bool isPrimary:
        Quickshell.screens.length > 0 && root.modelData === Quickshell.screens[0]

    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    Process {
        id: queryProc
        command: ["bash", "-c",
            'name="$1"; ' +
            'line=$(awww query 2>/dev/null | grep -m1 -- "$name:"); ' +
            'img=$(printf "%s" "$line" | sed -n "s/.*image: //p"); ' +
            '[ -n "$img" ] || exit 0; ' +
            'l="$(dirname "$img")/lyrics.qml"; ' +
            '[ -f "$l" ] && printf "%s" "$l"',
            "_", root.modelData ? root.modelData.name : ""]
        stdout: StdioCollector {
            onStreamFinished: root.lyricsPath = text.trim()
        }
    }

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

    Component.onCompleted: queryProc.running = true

    Timer {
        interval: 2000
        repeat: true
        running: root.lyricsPath === "" && root.retriesLeft > 0
        onTriggered: {
            root.retriesLeft--
            queryProc.running = true
        }
    }

    Connections {
        target: ControlBus
        function onWallpaperChanged() {
            root.retriesLeft = 10
            queryProc.running = true
        }
        function onThemeReloadRequested() {
            root.reloadNonce++
            root.retriesLeft = 10
            queryProc.running = true
        }
    }
}
