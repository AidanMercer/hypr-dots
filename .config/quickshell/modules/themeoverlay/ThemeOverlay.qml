import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"

// Per-monitor desktop overlay that belongs to the *active theme* — a free-form
// scenery layer on top of the wallpaper. Same loader idea as ThemeClock: each
// theme folder (~/.config/themes/<name>/) may drop an overlay.qml next to its
// wallpaper; this window finds the theme folder via awww and loads it if present.
// No overlay.qml → nothing renders.
//
// Bottom layer (above wallpaper, below windows) and fully click-through, so it's
// purely decorative — a HUD frame, telemetry, whatever the theme wants.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-themeoverlay"
    WlrLayershell.layer: WlrLayer.Bottom

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}                         // click-through: it's just scenery
    visible: overlayPath !== ""

    property string overlayPath: ""
    property int retriesLeft: 10

    // Encode each segment so theme names with spaces ("your name") survive.
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
            'c="$(dirname "$img")/overlay.qml"; ' +
            '[ -f "$c" ] && printf "%s" "$c"',
            "_", root.modelData ? root.modelData.name : ""]
        stdout: StdioCollector {
            onStreamFinished: root.overlayPath = text.trim()
        }
    }

    Loader {
        anchors.fill: parent
        active: root.overlayPath !== ""
        source: root.overlayPath !== "" ? root.fileUrl(root.overlayPath) : ""
    }

    Component.onCompleted: queryProc.running = true

    Timer {
        interval: 2000
        repeat: true
        running: root.overlayPath === "" && root.retriesLeft > 0
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
    }
}
