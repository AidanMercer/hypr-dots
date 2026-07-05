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
    property bool wantsPal: false               // widget declares `property var pal`
    property int reloadNonce: 0

    property ThemePalette pal: ThemePalette { themeDir: root.themeDir }

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
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\t")
                const changed = parts[0] !== root.lyricsPath || (parts.length > 1) !== root.wantsPal
                root.wantsPal = parts.length > 1
                root.lyricsPath = parts[0]
                if (changed) root.remount()
            }
        }
    }
    // Build the lookup command from the CURRENT themeDir at call time, NOT via a
    // declarative `command: [...root.themeDir]` binding. On a theme switch the
    // onThemeDirChanged handler fires BEFORE such a binding re-evaluates, so the
    // process would launch with the PREVIOUS theme's dir and load the wrong widget
    // (the one-behind bug). Reading themeDir at start time always sees the new value.
    function rescan() {
        existProc.command = ["bash", "-c",
            'd="$1"; f="$d/lyrics.qml"; { [ -n "$d" ] && [ -f "$f" ]; } || exit 0; ' +
            'printf "%s" "$f"; grep -q "property var pal" "$f" && printf "\\tPAL"; true',
            "_", root.themeDir]
        existProc.running = true
    }
    onThemeDirChanged: rescan()

    Loader {
        id: lyricsLoader
        anchors.fill: parent
        onLoaded: if (item && item.hasOwnProperty("isPrimary")) item.isPrimary = root.isPrimary
    }
    // setSource instead of a source binding so the widget gets `pal` as an
    // initial property — its bindings never see pal undefined. Called from the
    // exist-check collector (path/pal answer changed) and on nonce bumps.
    function remount() {
        if (root.lyricsPath === "") { lyricsLoader.source = ""; return }
        const url = root.fileUrl(root.lyricsPath) + "?v=" + root.reloadNonce
        lyricsLoader.setSource(url, root.wantsPal ? { pal: root.pal } : {})
    }
    onReloadNonceChanged: remount()

    // Hot-reload: watch the loaded file ourselves (quickshell only watches its own
    // config tree, not the theme dirs) and bump the ?v= nonce on save to recompile.
    // Rescan too, so adding/removing the widget's `pal` property takes on save.
    FileView {
        path: root.lyricsPath
        watchChanges: root.lyricsPath !== ""
        printErrors: false
        onFileChanged: { root.rescan(); root.reloadNonce++ }
    }
    // keep it correct if the screen list reorders after load
    onIsPrimaryChanged: if (lyricsLoader.item && lyricsLoader.item.hasOwnProperty("isPrimary"))
                            lyricsLoader.item.isPrimary = root.isPrimary

    Component.onCompleted: rescan()

    Connections {
        target: ControlBus
        function onThemeReloadRequested() {
            root.reloadNonce++
            root.rescan()
        }
    }
}
