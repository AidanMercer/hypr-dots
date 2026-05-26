import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"

// Fullscreen, transparent layer-shell overlay holding the status card (Network
// / Sound / Bluetooth / Power, with an uptime header). The card is positioned
// just under the bar, centred on the StatusButton; clicking anywhere on the
// surrounding scrim dismisses it.
//
// We use a scrim rather than HyprlandFocusGrab because the grab races the
// popup's mapping and often fails to attach (so click-outside never closes it).
// The Launcher uses this same proven scrim pattern.
PanelWindow {
    id: root

    property var barWindow
    property real anchorCenterX: 0
    // The popup opens only when ControlBus names this popup's monitor, so `open`
    // is a read-only reflection of the shared bus rather than a local toggle.
    readonly property string monitorName: barWindow && barWindow.screen ? barWindow.screen.name : ""
    readonly property bool open: monitorName !== "" && ControlBus.openMonitor === monitorName
    property int currentTab: 0  // 0 = network, 1 = sound, 2 = bluetooth, 3 = power

    // When the popup opens (via click or Super+M) focus the card so it receives
    // key events; Left/Right (or Tab) switch tabs, Up/Down walk the rows inside
    // the active tab, Enter acts on the highlighted row, Esc closes. See the
    // nav* helpers below and card.Keys further down.
    onOpenChanged: if (open) { resetNav(); Qt.callLater(card.forceActiveFocus) }

    // The four tab content items, indexed to line up with `tabs`/`currentTab`.
    // ControlPopup owns the Up/Down traversal (the wrap-around math lives here,
    // once); each tab only exposes navCount + activateNav() and highlights its
    // own row at navIndex.
    //
    // Populated in Component.onCompleted (not as a `[networkTab, …]` binding):
    // those ids live in nested delegates that don't exist yet while root's
    // property bindings first evaluate, so an eager binding throws "not defined".
    property var tabItems: []
    readonly property var activeTab: tabItems.length === tabs.length ? tabItems[currentTab] : null
    Component.onCompleted: tabItems = [networkTab, soundTab, bluetoothTab, powerTab]

    // Move the highlight within the active tab's list, wrapping at the ends. A
    // fresh tab has navIndex -1 (nothing highlighted): the first Down lands on
    // row 0, the first Up on the last row.
    function navMove(delta) {
        const t = activeTab
        if (!t || t.navCount === 0) return
        if (t.navIndex < 0) t.navIndex = delta > 0 ? 0 : t.navCount - 1
        else t.navIndex = (t.navIndex + delta + t.navCount) % t.navCount
    }

    // Enter/Return acts on the highlighted row (connect wifi, switch audio
    // device, (dis)connect a bluetooth device, run a power action).
    function navActivate() {
        const t = activeTab
        if (t && t.navIndex >= 0 && t.navIndex < t.navCount) t.activateNav()
    }

    // Clear every tab's highlight, so navigation starts fresh on open and when
    // switching tabs rather than resuming a stale (or now out-of-range) row.
    function resetNav() {
        for (let i = 0; i < tabItems.length; i++) tabItems[i].navIndex = -1
    }

    onCurrentTabChanged: resetNav()

    // Bare modifier keys that should NOT trigger the "any key closes it"
    // dismissal — otherwise tapping Shift/Ctrl/Alt/Super would shut the popup.
    readonly property var modifierKeys: [
        Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr,
        Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R,
        Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_ScrollLock
    ]

    // network status passed through from the StatusButton into the Network tab
    property string connType: "none"
    property string connName: ""
    // uptime string passed through from the StatusButton into the header
    property string uptimeText: ""
    signal connectionChanged()

    // Appear on the same monitor as the bar that owns this popup.
    screen: barWindow ? barWindow.screen : null

    WlrLayershell.namespace: "quickshell-control-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    // Grab the keyboard only while open so arrow/Tab/Esc reach the popup, and the
    // focused window keeps the keyboard the rest of the time.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    // Cover the full output (including the strip under the bar) so a click
    // anywhere outside the card is caught.
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Stay mapped through the close animation, like the launcher.
    visible: open || exitTrans.running

    readonly property string iconArch: String.fromCodePoint(0xF303) // nf-linux-archlinux

    readonly property var tabs: [
        { label: "Network",   glyph: 0xF05A9 },
        { label: "Sound",     glyph: 0xF057E },
        { label: "Bluetooth", glyph: 0xF00AF },
        { label: "Power",     glyph: 0xF0425 }
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
        // Centre the card under the button, clamped to stay on-screen.
        x: Math.max(8, Math.min(root.width - width - 8, root.anchorCenterX - width / 2))
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
            width: 360
            height: content.implicitHeight + 32
            radius: Theme.popupRadius
            color: Theme.glassBg
            border.color: Theme.glassBorder
            border.width: 1
            focus: true

            // Left/Right (and Tab/Shift+Tab) wrap across the tab strip; Up/Down
            // walk the rows inside the active tab; Enter acts on the highlighted
            // row; Esc dismisses. Focus is forced here on open via
            // root.onOpenChanged.
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
                    // Any other key (a letter, digit, etc.) dismisses the popup —
                    // a "just start typing to bail out" escape hatch. Bare
                    // modifier taps are filtered above so they don't close it.
                    ControlBus.close(); e.accepted = true
                }
            }

            // Swallow clicks on the card so they don't fall through to the scrim.
            MouseArea { anchors.fill: parent }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: parent.radius
                anchors.rightMargin: parent.radius
                anchors.topMargin: 1
                height: 1
                color: Theme.glassHighlight
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
                        color: Theme.accent
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
                            radius: 10
                            color: selected ? Theme.rowSelected
                                : (tabMa.containsMouse ? Theme.rowHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCodePoint(tab.modelData.glyph)
                                    font.family: Theme.icon
                                    font.pixelSize: 14
                                    color: tab.selected ? Theme.accent : Theme.textSecondary
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
            }
        }
    }
}
