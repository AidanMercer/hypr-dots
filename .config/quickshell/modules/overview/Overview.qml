import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "../common"

// Fullscreen "zoom out" overview: every occupied workspace on the focused
// monitor as a mini-monitor tile, with each open window drawn at its real
// position/size and filled with a LIVE screencopy of that window. Click a
// window to focus it, click a tile to jump to that workspace. Esc / click-out
// dismisses. Toggled over IPC: `qs ipc call overview toggle` (Super+Tab).
//
// Skeleton mirrors Launcher.qml (transparent Overlay layer-shell, keyboard grab
// only while open). The two pieces that make live thumbnails work:
//   - Hyprland.toplevels gives each window's geometry via .lastIpcObject
//     (at = [x,y], size = [w,h], all in logical coords), and
//   - the same window exposes .wayland, a capturable Toplevel handle that
//     ScreencopyView renders live.
PanelWindow {
    id: root

    property bool open: false
    // Captured at open() so a wandering cursor can't remap the window mid-use.
    property var targetScreen: null
    // The Hyprland monitor we're mirroring (geometry source). Captured too.
    property var mon: null
    screen: targetScreen

    WlrLayershell.namespace: "quickshell-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || exitTrans.running

    // Keep the (lazy) desktop-entry DB alive so icon lookups resolve, same
    // trick the bar's Workspaces.qml uses.
    readonly property int _desktopKeepAlive: DesktopEntries.applications.values.length

    // ---- monitor geometry (logical coords) -----------------------------
    // hyprctl reports monitor width/height in physical px and a fractional
    // scale; logical size = physical / scale. Window at/size are already
    // logical, so everything maps once we divide the monitor by its scale.
    readonly property var monObj: mon?.lastIpcObject ?? null
    readonly property real monX: monObj?.x ?? 0
    readonly property real monY: monObj?.y ?? 0
    readonly property real monScale: monObj?.scale ?? 1
    readonly property real monLogW: monObj ? monObj.width / monScale : 1920
    readonly property real monLogH: monObj ? monObj.height / monScale : 1080
    readonly property int monId: monObj?.id ?? 0

    // ---- windows + workspaces on this monitor --------------------------
    // Live list of this monitor's real windows (skip special/scratch, which
    // have negative workspace ids).
    readonly property var wins: Hyprland.toplevels.values.filter(t => {
        const o = t.lastIpcObject
        return o && o.monitor === monId && o.workspace && o.workspace.id > 0
    })
    // Workspaces to show: any that hold a window, plus the currently active one
    // so an empty active workspace still gets a tile. Sorted ascending.
    readonly property var wsIds: {
        const ids = new Set()
        for (const t of wins) ids.add(t.lastIpcObject.workspace.id)
        const act = mon?.activeWorkspace?.id ?? 1
        ids.add(act)
        const arr = Array.from(ids).filter(id => id > 0).sort((a, b) => a - b)
        return arr.length ? arr : [act]
    }
    readonly property int activeWsId: mon?.activeWorkspace?.id ?? 1

    function winsOnWs(wsId) {
        return wins.filter(t => t.lastIpcObject.workspace.id === wsId)
    }

    // ---- tile sizing ---------------------------------------------------
    // Square-ish grid; tiles scale to fit ~82% of the screen width.
    readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(wsIds.length)))
    readonly property real gridMaxW: (targetScreen?.width ?? 1920) * 0.82
    readonly property real tileW: Math.min(460, gridMaxW / cols - 20)
    // Scale from logical monitor px -> tile px; every window box uses this.
    readonly property real s: tileW / monLogW
    readonly property real tileH: monLogH * s

    // Resolve a window class to an icon URL, degrading to the class name then a
    // generic app icon (same ladder as Workspaces.qml).
    function iconFor(cls) {
        if (!cls) return Quickshell.iconPath("application-x-executable")
        const e = DesktopEntries.heuristicLookup(cls)
        const name = (e && e.icon) ? e.icon : cls.toLowerCase()
        return Quickshell.iconPath(name, "application-x-executable")
    }

    // ---- open / close --------------------------------------------------
    function openView() {
        const m = Hyprland.focusedMonitor
        root.mon = m
        root.targetScreen = m ? (Quickshell.screens.find(sc => sc.name === m.name) ?? null) : null
        Hyprland.refreshToplevels()   // toplevels can be empty until kicked
        root.open = true
        Qt.callLater(keyCatch.forceActiveFocus)
    }
    function closeView() { root.open = false }
    function focusWindow(addr) {
        if (addr) Hyprland.dispatch("focuswindow address:" + addr)
        closeView()
    }
    function gotoWs(wsId) {
        Hyprland.dispatch("workspace " + wsId)
        closeView()
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.open ? root.closeView() : root.openView() }
    }

    // Esc / Super+Tab-again handling. A focused invisible item catches keys
    // because the layer-shell grab needs *something* holding active focus.
    Item {
        id: keyCatch
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { root.closeView(); e.accepted = true }
        }
    }

    // Dim scrim; click-out closes.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.38 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.closeView()
        }
    }

    // ---- the grid ------------------------------------------------------
    Item {
        id: stage
        anchors.centerIn: parent
        width: grid.width
        height: grid.height
        opacity: 0
        scale: 0.94
        transformOrigin: Item.Center

        states: State {
            name: "shown"; when: root.open
            PropertyChanges { target: stage; opacity: 1; scale: 1 }
        }
        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                    SpringAnimation { property: "scale"; spring: 3; damping: 0.34; epsilon: 0.001 }
                }
            },
            Transition {
                id: exitTrans; from: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 150; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; duration: 150; easing.type: Easing.InCubic }
                }
            }
        ]

        Grid {
            id: grid
            columns: root.cols
            spacing: 20

            Repeater {
                model: root.wsIds

                // ── one workspace tile ──
                delegate: Column {
                    id: tile
                    required property var modelData
                    readonly property int wsId: modelData
                    readonly property bool isActive: root.activeWsId === wsId
                    spacing: 6

                    Text {
                        text: "Workspace " + tile.wsId
                        font.pixelSize: 12
                        font.weight: tile.isActive ? Font.DemiBold : Font.Normal
                        color: tile.isActive ? Theme.accent : Theme.textSecondary
                    }

                    // mini-monitor surface
                    Rectangle {
                        width: root.tileW
                        height: root.tileH
                        radius: 12
                        clip: true
                        color: Theme.glassBg
                        border.width: tile.isActive ? 2 : 1
                        border.color: tile.isActive ? Theme.accent : Theme.glassBorder

                        // click empty area -> switch to this workspace
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.gotoWs(tile.wsId)
                        }

                        // ── windows on this workspace ──
                        Repeater {
                            model: root.winsOnWs(tile.wsId)

                            delegate: Item {
                                id: box
                                required property var modelData
                                readonly property var o: modelData.lastIpcObject
                                // logical position within the monitor -> tile px
                                x: Math.max(0, (o.at[0] - root.monX) * root.s)
                                y: Math.max(0, (o.at[1] - root.monY) * root.s)
                                width: Math.max(8, o.size[0] * root.s)
                                height: Math.max(8, o.size[1] * root.s)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    clip: true
                                    color: Qt.rgba(0, 0, 0, 0.25)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)

                                    // Fallback shown when there's no live frame
                                    // (windows on non-visible workspaces aren't
                                    // composited, so screencopy has no content).
                                    IconImage {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width, parent.height) * 0.5
                                        height: width
                                        source: root.iconFor(box.o.class)
                                    }

                                    // Live capture, only while open so we don't
                                    // keep GPU copies running in the background.
                                    Loader {
                                        anchors.fill: parent
                                        active: root.open && !!box.modelData.wayland
                                        sourceComponent: ScreencopyView {
                                            captureSource: box.modelData.wayland
                                            live: root.open
                                            paintCursor: false
                                            opacity: hasContent ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    // click window -> focus it (also switches ws)
                                    onClicked: root.focusWindow(box.o.address)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
