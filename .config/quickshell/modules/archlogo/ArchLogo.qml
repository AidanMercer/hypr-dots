import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"

// Centerpiece desktop widget: the audio-reactive logo, owned by the active theme.
//
// Each theme folder (~/.config/themes/<name>/) may drop a cava.qml next to its
// wallpaper. This window asks awww which wallpaper the monitor is showing, walks
// up to that theme folder, and loads its cava.qml if present. No cava.qml → the
// default ArchVisualizer (the Arch triangle) is shown instead. Same loader idea
// as ThemeClock, so a theme can ship both a clock.qml and a cava.qml.
//
// Bottom layer (above wallpaper, below windows) and fully click-through — passive
// scenery. The layer surface and the awww query live here; the loaded visual just
// draws into it.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-archlogo"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}                              // click-through scenery

    property string themeDir: ActiveTheme.dirFor(root.modelData ? root.modelData.name : "")
    property string cavaPath: ""                 // theme's cava.qml, "" if none
    property bool checked: false                 // existence check has returned
    property int reloadNonce: 0

    // Encode each segment so theme names with spaces ("your name") survive.
    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    // ActiveTheme already knows this monitor's theme folder (one shared awww query);
    // we just confirm it ships a cava.qml. `checked` flips once the answer is in, so
    // the default Arch visualizer only appears after we know there's no theme cava.
    Process {
        id: existProc
        command: ["bash", "-c",
            'd="$1"; [ -n "$d" ] && [ -f "$d/cava.qml" ] && printf "%s/cava.qml" "$d"',
            "_", root.themeDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.cavaPath = text.trim()
                root.checked = true
            }
        }
    }
    onThemeDirChanged: { root.checked = false; existProc.running = true }

    // theme's own visualizer
    Loader {
        anchors.fill: parent
        active: root.cavaPath !== ""
        source: root.cavaPath !== "" ? root.fileUrl(root.cavaPath) + "?v=" + root.reloadNonce : ""
    }

    // Hot-reload: watch the loaded file ourselves (quickshell only watches its own
    // config tree, not the theme dirs) and bump the ?v= nonce on save to recompile.
    FileView {
        path: root.cavaPath
        watchChanges: root.cavaPath !== ""
        printErrors: false
        onFileChanged: root.reloadNonce++
    }

    // default Arch visualizer — once we know the theme ships no cava.qml
    Loader {
        anchors.fill: parent
        active: root.checked && root.cavaPath === ""
        sourceComponent: archComponent
    }
    Component {
        id: archComponent
        ArchVisualizer {}
    }

    Component.onCompleted: existProc.running = true

    Connections {
        target: ControlBus
        function onThemeReloadRequested() {
            root.reloadNonce++
            root.checked = false
            existProc.running = true
        }
    }
}
