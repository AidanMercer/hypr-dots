import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"

// Fullscreen, transparent layer-shell overlay holding the status card (Network /
// Sound / Bluetooth / Power / Display, with an uptime header). Created once per
// monitor in shell.qml — decoupled from the bar — so it works no matter which
// bar (default or a theme's own) is loaded. Opens when ControlBus names this
// monitor; clicking the surrounding scrim dismisses it.
//
// It owns its own uptime + network polling (so it doesn't depend on the bar's
// StatusButton) and switches to cyberpunk chrome when the active theme sets
// `cyber = true` in its config.toml — the reused tabs keep their own styling.
//
// We use a scrim rather than HyprlandFocusGrab because the grab races the popup's
// mapping and often fails to attach. The Launcher uses this same scrim pattern.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property bool open: monitorName !== "" && ControlBus.openMonitor === monitorName
    property int currentTab: 0  // 0 = network, 1 = sound, 2 = bluetooth, 3 = power, 4 = display

    // ── theme chrome: cyberpunk when the theme opts in, glass otherwise ──
    readonly property bool cyber: ThemeConfig.cyber
    readonly property color accentCol: ThemeConfig.accent
    readonly property color cardBg: cyber ? Qt.rgba(0.03, 0.03, 0.045, 0.93) : Theme.glassBg
    readonly property color cardBorder: cyber ? accentCol : Theme.glassBorder
    readonly property int cardRadius: cyber ? 5 : Theme.popupRadius

    onOpenChanged: if (open) { resetNav(); Qt.callLater(card.forceActiveFocus) }

    function tabList() { return [networkTab, soundTab, bluetoothTab, powerTab, displayTab] }
    function activeTabItem() { return tabList()[currentTab] }

    function navMove(delta) {
        const t = activeTabItem()
        if (!t || t.navCount === 0) return
        if (t.navIndex < 0) t.navIndex = delta > 0 ? 0 : t.navCount - 1
        else t.navIndex = (t.navIndex + delta + t.navCount) % t.navCount
    }
    function navActivate() {
        const t = activeTabItem()
        if (t && t.navIndex >= 0 && t.navIndex < t.navCount) t.activateNav()
    }
    function resetNav() {
        const ts = tabList()
        for (let i = 0; i < ts.length; i++) ts[i].navIndex = -1
    }
    onCurrentTabChanged: resetNav()

    readonly property var modifierKeys: [
        Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr,
        Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R,
        Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_ScrollLock
    ]

    // ── uptime: read /proc/uptime, tick locally, re-sync to correct drift ──
    property real uptimeSeconds: 0
    readonly property string uptimeText: "up " + formatUptime(uptimeSeconds)
    function formatUptime(s) {
        const total = Math.floor(s)
        const d = Math.floor(total / 86400)
        const h = Math.floor((total % 86400) / 3600)
        const m = Math.floor((total % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }
    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const first = parseFloat(text.trim().split(/\s+/)[0])
                if (!isNaN(first)) root.uptimeSeconds = first
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.uptimeSeconds += 1 }
    Timer { interval: 300000; running: true; repeat: true; onTriggered: uptimeProc.running = true }

    // ── network: lightweight status poll feeding the Network tab ──
    property string connType: "none"   // "wifi" | "ethernet" | "none"
    property string connName: ""
    signal connectionChanged()
    function refreshNet() { netProc.running = true }
    function parseNm(raw) {
        let nextType = "none", nextName = ""
        for (const line of raw.trim().split("\n")) {
            if (!line) continue
            const parts = line.split(":")
            const type = parts[0], state = parts[1], name = parts.slice(2).join(":")
            if (type === "loopback") continue
            if (state !== "connected") continue
            if (type === "wifi") { nextType = "wifi"; nextName = name; break }
            if (type === "ethernet" && nextType === "none") { nextType = "ethernet"; nextName = name }
        }
        connType = nextType
        connName = nextName
    }
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseNm(text) }
    }
    // poll faster while open, lazily while closed
    Timer {
        interval: root.open ? 5000 : 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: netProc.running = true
    }
    onConnectionChanged: refreshNet()

    WlrLayershell.namespace: "quickshell-control-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || exitTrans.running

    readonly property string iconArch: String.fromCodePoint(0xF303) // nf-linux-archlinux

    readonly property var tabs: [
        { label: "Network",   glyph: 0xF05A9 },
        { label: "Sound",     glyph: 0xF057E },
        { label: "Bluetooth", glyph: 0xF00AF },
        { label: "Power",     glyph: 0xF0425 },
        { label: "Display",   glyph: 0xF0379 }
    ]

    // ── scrim: transparent (no dimming), click-outside to dismiss ──
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: ControlBus.close()
    }

    Item {
        id: morph
        width: card.width
        height: card.height
        // top-centre, just under the bar
        x: Math.max(8, (root.width - width) / 2)
        y: Theme.barHeight + 4
        opacity: 0
        scale: 0.78
        transformOrigin: Item.Top

        states: State {
            name: "shown"
            when: root.open
            PropertyChanges { target: morph; opacity: 1; scale: 1 }
        }

        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 220; easing.type: Easing.OutCubic }
                    SpringAnimation { property: "scale"; spring: 3; damping: 0.32; epsilon: 0.001 }
                }
            },
            Transition {
                id: exitTrans
                from: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; duration: 180; easing.type: Easing.InCubic }
                }
            }
        ]

        Rectangle {
            id: card
            width: 432
            height: content.implicitHeight + 32
            radius: root.cardRadius
            color: root.cardBg
            border.color: root.cardBorder
            border.width: root.cyber ? 1.4 : 1
            focus: true

            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) {
                    ControlBus.close(); e.accepted = true
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) {
                    root.currentTab = (root.currentTab + 1) % root.tabs.length
                    e.accepted = true
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) {
                    root.currentTab = (root.currentTab + root.tabs.length - 1) % root.tabs.length
                    e.accepted = true
                } else if (e.key === Qt.Key_Down) {
                    root.navMove(1); e.accepted = true
                } else if (e.key === Qt.Key_Up) {
                    root.navMove(-1); e.accepted = true
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    root.navActivate(); e.accepted = true
                } else if (!root.modifierKeys.includes(e.key)) {
                    ControlBus.close(); e.accepted = true
                }
            }

            MouseArea { anchors.fill: parent }

            // top highlight (glass) / neon accent rule (cyber)
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: parent.radius
                anchors.rightMargin: parent.radius
                anchors.topMargin: 1
                height: root.cyber ? 2 : 1
                color: root.cyber ? root.accentCol : Theme.glassHighlight
                opacity: root.cyber ? 0.8 : 1
            }

            Column {
                id: content
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // ── header: Arch glyph + uptime ──
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.iconArch
                        color: root.cyber ? root.accentCol : Theme.accent
                        font.family: Theme.icon
                        font.pixelSize: 16
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.uptimeText
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.mono
                    }
                }

                // ── segmented tab bar ──
                Row {
                    id: tabBar
                    width: parent.width
                    height: 32
                    spacing: 4

                    Repeater {
                        model: root.tabs

                        delegate: Rectangle {
                            id: tab
                            required property int index
                            required property var modelData
                            readonly property bool selected: root.currentTab === index

                            width: (tabBar.width - tabBar.spacing * (root.tabs.length - 1)) / root.tabs.length
                            height: tabBar.height
                            radius: root.cyber ? 4 : 10
                            color: selected
                                ? (root.cyber ? Qt.rgba(root.accentCol.r, root.accentCol.g, root.accentCol.b, 0.16) : Theme.rowSelected)
                                : (tabMa.containsMouse ? Theme.rowHover : "transparent")
                            border.width: (root.cyber && selected) ? 1 : 0
                            border.color: root.accentCol
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCodePoint(tab.modelData.glyph)
                                    font.family: Theme.icon
                                    font.pixelSize: 14
                                    color: tab.selected ? (root.cyber ? root.accentCol : Theme.accent) : Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tab.modelData.label
                                    font.pixelSize: 11
                                    color: tab.selected ? Theme.textBright : Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }

                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentTab = tab.index
                            }
                        }
                    }
                }

                // ── tab contents (only the active one is visible/sized) ──
                NetworkTab {
                    id: networkTab
                    width: parent.width
                    visible: root.currentTab === 0
                    active: root.open && root.currentTab === 0
                    connType: root.connType
                    connName: root.connName
                    onConnectionChanged: root.connectionChanged()
                }

                SoundTab {
                    id: soundTab
                    width: parent.width
                    visible: root.currentTab === 1
                }

                BluetoothTab {
                    id: bluetoothTab
                    width: parent.width
                    visible: root.currentTab === 2
                    active: root.open && root.currentTab === 2
                }

                PowerTab {
                    id: powerTab
                    width: parent.width
                    visible: root.currentTab === 3
                    onActionTriggered: ControlBus.close()
                }

                DisplayTab {
                    id: displayTab
                    width: parent.width
                    visible: root.currentTab === 4
                    active: root.open && root.currentTab === 4
                }
            }
        }
    }
}
