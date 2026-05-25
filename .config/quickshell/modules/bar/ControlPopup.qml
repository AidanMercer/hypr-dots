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
    property bool open: false
    property int currentTab: 0  // 0 = network, 1 = sound, 2 = bluetooth, 3 = power

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
        onClicked: root.open = false
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
                    width: parent.width
                    visible: root.currentTab === 0
                    active: root.open && root.currentTab === 0
                    connType: root.connType
                    connName: root.connName
                    onConnectionChanged: root.connectionChanged()
                }

                SoundTab {
                    width: parent.width
                    visible: root.currentTab === 1
                }

                BluetoothTab {
                    width: parent.width
                    visible: root.currentTab === 2
                    active: root.open && root.currentTab === 2
                }

                PowerTab {
                    width: parent.width
                    visible: root.currentTab === 3
                    onActionTriggered: root.open = false
                }
            }
        }
    }
}
