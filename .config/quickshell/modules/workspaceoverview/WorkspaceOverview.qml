import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "../common"

// Workspace overview / radial exposé. The focused window sits dead-center;
// every other open window fans out around it on a ring, one tile per window,
// evenly spaced at all angles. Click a tile (or the center) to focus that
// window — focusing jumps to its workspace, so this doubles as a switch-
// anywhere. Toggled via `qs ipc call workspaceOverview toggle` (Super+Tab).
//
// Phase 1: icon + title tiles, click/esc, spring-out zoom. Live thumbnails
// and keyboard rotation come next.
PanelWindow {
    id: root

    property bool open: false
    property bool closing: false

    // Captured at open() so a follow-mouse cursor can't remap the window mid-use.
    property var targetScreen: null
    screen: targetScreen

    WlrLayershell.namespace: "quickshell-workspaceoverview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || closing

    // ---- geometry ----
    readonly property int tileW: 280
    readonly property int tileH: 174
    readonly property int centerW: 384
    readonly property int centerH: 236
    // how far the surrounding tiles sit from center — wide enough that the ring
    // tiles clear the (larger) center tile at every angle
    readonly property real ringRadius: Math.min(width, height) * 0.40

    property int hovered: -1

    // 0 closed, 1 open. Every tile eases its position out from the center and
    // scales up off this — that's the zoom-out pop. OutBack overshoots on the
    // way in so the ring fans slightly past its rest and settles.
    property real reveal: open ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.open ? 300 : 200
            easing.type: root.open ? Easing.OutBack : Easing.InCubic
        }
    }

    // ---- window model ----
    readonly property var windows: root.open ? root.buildWindows() : []
    function buildWindows() {
        return Hyprland.toplevels.values.map(t => {
            const o = t.lastIpcObject || {}
            return {
                address: o.address || "",
                title: o.title || "",
                cls: o.class || "",
                active: o.focusHistoryID === 0,
            }
        }).filter(w => w.address)   // freshly-opened windows arrive address-less
    }
    readonly property var activeWin: root.windows.find(w => w.active) ?? null
    readonly property var ringWins: root.windows.filter(w => !w.active)

    // one flat list — center first, then the ring — so a single Repeater + one
    // delegate lays them all out. Each entry carries its rest offset from center.
    readonly property var tiles: root.layoutTiles()
    function layoutTiles() {
        const out = []
        if (root.activeWin)
            out.push({ win: root.activeWin, w: centerW, h: centerH, rx: 0, ry: 0, center: true })
        const ring = root.ringWins
        const n = ring.length
        for (let i = 0; i < n; i++) {
            const ang = -Math.PI / 2 + i * 2 * Math.PI / n   // first tile at 12 o'clock
            out.push({
                win: ring[i], w: tileW, h: tileH,
                rx: Math.cos(ang) * ringRadius,
                ry: Math.sin(ang) * ringRadius,
                center: false,
            })
        }
        return out
    }

    function iconForClass(cls) {
        if (!cls) return Quickshell.iconPath("application-x-executable")
        const entry = DesktopEntries.heuristicLookup(cls)
        const name = (entry && entry.icon) ? entry.icon : cls.toLowerCase()
        return Quickshell.iconPath(name, "application-x-executable")
    }

    function focusWindow(addr) {
        if (!addr) return
        Hyprland.dispatch("focuswindow address:" + addr)
        root.closeMenu()
    }

    // keep the ring fresh if windows open/close/move while the overview is up
    Connections {
        target: Hyprland
        enabled: root.open
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow":
            case "closewindow":
            case "movewindow":
            case "movewindowv2":
            case "activewindowv2":
                Hyprland.refreshToplevels()
            }
        }
    }

    function openMenu() {
        const m = Hyprland.focusedMonitor
        targetScreen = m ? (Quickshell.screens.find(s => s.name === m.name) ?? null) : null
        closing = false
        hovered = -1
        Hyprland.refreshToplevels()
        open = true
        Qt.callLater(() => keyCatcher.forceActiveFocus())
    }
    function closeMenu() {
        if (!open) return
        open = false
        closing = true
        closeHold.restart()
    }
    Timer { id: closeHold; interval: 300; onTriggered: root.closing = false }

    IpcHandler {
        target: "workspaceOverview"
        function toggle(): void { root.open ? root.closeMenu() : root.openMenu() }
    }

    // darker than the theme switcher's gallery scrim — an exposé wants the
    // wallpaper pushed back so the tiles read.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.open ? 0.42 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // click-outside to dismiss
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeMenu()
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { root.closeMenu(); e.accepted = true }
        }
    }

    // ---- the radial field ----
    Repeater {
        model: root.tiles

        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property var win: modelData.win
            readonly property bool isCenter: modelData.center
            readonly property bool hot: root.hovered === index

            width: modelData.w
            height: modelData.h
            // rest position eased out from center by `reveal`; hover raises z
            x: root.width / 2 + modelData.rx * root.reveal - width / 2
            y: root.height / 2 + modelData.ry * root.reveal - height / 2
            scale: 0.55 + 0.45 * root.reveal
            opacity: root.reveal
            z: hot ? 20 : (isCenter ? 5 : 1)

            // lift each tile off the busy desktop behind it
            RectangularShadow {
                anchors.fill: parent
                radius: Theme.popupRadius
                blur: 40
                offset: Qt.vector2d(0, 16)
                color: Qt.rgba(0, 0, 0, 0.5)
                opacity: root.reveal
            }

            Rectangle {
                id: card
                anchors.fill: parent
                radius: Theme.popupRadius
                color: Theme.menuBg
                border.color: tile.hot ? Theme.accent
                           : (tile.isCenter ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                                            : Theme.glassBorder)
                border.width: tile.hot || tile.isCenter ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 120 } }

                scale: tile.hot ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: parent.radius
                    anchors.rightMargin: parent.radius
                    height: 1
                    color: Theme.glassHighlight
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: tile.isCenter ? 14 : 10

                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tile.isCenter ? 68 : 44
                        height: width
                        source: root.iconForClass(tile.win.cls)
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.win.title || tile.win.cls || "window"
                        textFormat: Text.PlainText
                        color: tile.hot ? Theme.textBright : Theme.textPrimary
                        font.pixelSize: tile.isCenter ? 16 : 13
                        font.weight: tile.isCenter ? Font.Medium : Font.Normal
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: tile.win.cls.length > 0
                        text: tile.win.cls
                        textFormat: Text.PlainText
                        color: Theme.textMuted
                        font.family: Theme.mono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hovered = tile.index
                    onExited: if (root.hovered === tile.index) root.hovered = -1
                    onClicked: root.focusWindow(tile.win.address)
                }
            }
        }
    }

    // empty state
    Text {
        anchors.centerIn: parent
        visible: root.open && root.windows.length === 0
        text: "No open windows"
        color: Theme.textMuted
        font.family: Theme.mono
        font.pixelSize: 15
        opacity: root.reveal
    }

    // hint
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 72
        visible: root.windows.length > 0
        text: "click a window to switch    esc to close"
        color: Theme.textMuted
        font.family: Theme.mono
        font.pixelSize: 11
        font.letterSpacing: 1
        opacity: root.reveal * 0.8
    }
}
