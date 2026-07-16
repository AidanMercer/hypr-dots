import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "../common"

// Per-monitor ambient particle layer owned by the active theme.
//
// Each theme folder (~/.config/themes/<name>/) may drop a particles.qml next to
// its wallpaper — petals, snow, embers, whatever fits. Same plumbing as the
// theme clock: Bottom layer (above the wallpaper, below real windows), fully
// click-through, pal injected, occluded pushed in so the drift pauses while the
// desktop isn't actually visible.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-themeparticles"
    WlrLayershell.layer: WlrLayer.Bottom

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}                         // click-through: it's just scenery
    visible: particlesPath !== "" && slotOn

    property string themeDir: ActiveTheme.dirFor(root.modelData ? root.modelData.name : "")
    // per-theme toggle (Super+Shift+/ → Settings); flipping it mounts/unmounts live
    readonly property bool slotOn: ThemeSettings.on(root.themeDir, "particles")
    onSlotOnChanged: remount()
    property string particlesPath: ""
    property bool wantsPal: false               // widget declares `property var pal`
    property int reloadNonce: 0

    property ThemePalette pal: ThemePalette { themeDir: root.themeDir }

    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    Process {
        id: existProc
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\t")
                const changed = parts[0] !== root.particlesPath || (parts.length > 1) !== root.wantsPal
                root.wantsPal = parts.length > 1
                root.particlesPath = parts[0]
                if (changed) root.remount()
            }
        }
    }
    // command built at call time, not bound — the one-behind trap (see ThemeClock)
    function rescan() {
        existProc.command = ["bash", "-c",
            'd="$1"; f="$d/particles.qml"; { [ -n "$d" ] && [ -f "$f" ]; } || exit 0; ' +
            'printf "%s" "$f"; grep -q "property var pal" "$f" && printf "\\tPAL"; true',
            "_", root.themeDir]
        existProc.running = true
    }
    onThemeDirChanged: rescan()

    Loader {
        id: widgetLoader
        anchors.fill: parent
        opacity: ControlBus.swapping ? 0 : 1
        Behavior on opacity {
            id: fadeBeh
            NumberAnimation { duration: ControlBus.swapping ? 140 : 450; easing.type: Easing.OutCubic }
        }
        onItemChanged: {
            if (!item || ControlBus.swapping) return
            fadeBeh.enabled = false
            opacity = 0
            fadeBeh.enabled = true
            opacity = Qt.binding(() => ControlBus.swapping ? 0 : 1)
        }
    }

    // Locked or covered by a fullscreen window → the drift pauses (same rule as
    // the theme clock; widgets gate their ParticleSystem on !occluded).
    readonly property var hyprMon: Hyprland.monitorFor(root.modelData)
    readonly property bool occluded: ControlBus.sessionLocked
        || Hyprland.toplevels.values.some(t =>
            t.wayland && t.wayland.fullscreen
            && t.monitor === root.hyprMon
            && t.workspace && t.workspace.active)
    Binding {
        target: widgetLoader.item
        property: "occluded"
        value: root.occluded
        when: widgetLoader.item !== null && widgetLoader.item.hasOwnProperty("occluded")
    }
    function remount() {
        if (root.particlesPath === "" || !root.slotOn) { widgetLoader.source = ""; return }
        const url = root.fileUrl(root.particlesPath) + "?v=" + root.reloadNonce
        widgetLoader.setSource(url, root.wantsPal ? { pal: root.pal } : {})
    }
    onReloadNonceChanged: remount()

    FileView {
        path: root.particlesPath
        watchChanges: root.particlesPath !== ""
        printErrors: false
        onFileChanged: { root.rescan(); root.reloadNonce++ }
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
