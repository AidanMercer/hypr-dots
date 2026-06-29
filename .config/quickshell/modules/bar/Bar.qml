import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"

// Top bar wrapper, owned by the active theme. Reserves the bar's height/exclusive
// zone, then loads either a theme's own bar.qml or the default BarContent. Same
// loader idea as ArchLogo/ThemeClock: a theme folder (~/.config/themes/<name>/)
// may drop a bar.qml next to its wallpaper; no bar.qml → the default bar shows.
//
// The theme's bar.qml is loaded by file path so it can't import the repo modules,
// so it's self-contained — it gets only its Hyprland screen, injected after load.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-bar"

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: "transparent"

    property string themeDir: ActiveTheme.dirFor(bar.screen ? bar.screen.name : "")
    property string barPath: ""                  // theme's bar.qml, "" if none
    property bool checked: false
    property int reloadNonce: 0

    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    // ActiveTheme already knows this monitor's theme folder (one shared awww query);
    // we just confirm it ships a bar.qml. `checked` flips once the answer is in, so
    // the default bar only appears after we know there's no theme bar.
    Process {
        id: existProc
        stdout: StdioCollector {
            onStreamFinished: {
                bar.barPath = text.trim()
                bar.checked = true
            }
        }
    }
    // Build the lookup command from the CURRENT themeDir at call time, NOT via a
    // declarative `command: [...bar.themeDir]` binding. On a theme switch the
    // onThemeDirChanged handler fires BEFORE such a binding re-evaluates, so the
    // process would launch with the PREVIOUS theme's dir and load the wrong widget
    // (the one-behind bug). Reading themeDir at start time always sees the new value.
    function rescan() {
        existProc.command = ["bash", "-c",
            'd="$1"; [ -n "$d" ] && [ -f "$d/bar.qml" ] && printf "%s/bar.qml" "$d"',
            "_", bar.themeDir]
        existProc.running = true
    }
    onThemeDirChanged: { bar.checked = false; rescan() }

    // theme's own bar — self-contained, gets its screen injected after load
    Loader {
        id: themeLoader
        anchors.fill: parent
        active: bar.barPath !== ""
        source: bar.barPath !== "" ? bar.fileUrl(bar.barPath) + "?v=" + bar.reloadNonce : ""
        onLoaded: if (item) item.barScreen = bar.screen
    }

    // Hot-reload: watch the loaded file ourselves (quickshell only watches its own
    // config tree, not the theme dirs) and bump the ?v= nonce on save to recompile.
    FileView {
        path: bar.barPath
        watchChanges: bar.barPath !== ""
        printErrors: false
        onFileChanged: bar.reloadNonce++
    }

    // default bar — once we know the theme ships no bar.qml
    Loader {
        anchors.fill: parent
        active: bar.checked && bar.barPath === ""
        sourceComponent: defaultContent
    }
    Component {
        id: defaultContent
        BarContent { barWindow: bar }
    }

    Component.onCompleted: rescan()

    Connections {
        target: ControlBus
        function onThemeReloadRequested() {
            bar.reloadNonce++
            bar.checked = false
            bar.rescan()
        }
    }
}
