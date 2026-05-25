import QtQuick
import Quickshell
import "../common"

// Single popup with a segmented tab bar switching between Network, Sound and
// Bluetooth tabs. Anchored under the combined ControlBubble on the right edge.
// The window height tracks whichever tab is visible (a Column drops invisible
// children from its implicit size), so the card resizes per tab.
PopupWindow {
    id: root

    property var barWindow
    property real anchorRight: 0
    property bool open: false
    property int currentTab: 0  // 0 = network, 1 = sound, 2 = bluetooth

    // network status passed through from the bubble into the Network tab
    property string connType: "none"
    property string connName: ""
    signal connectionChanged()

    anchor.window: barWindow
    anchor.rect.x: anchorRight - implicitWidth
    anchor.rect.y: barWindow ? barWindow.implicitHeight + 4 : 0
    implicitWidth: 340
    implicitHeight: content.implicitHeight + 32
    visible: open || exitTrans.running
    color: "transparent"

    readonly property var tabs: [
        { label: "Network",   glyph: 0xF05A9 },
        { label: "Sound",     glyph: 0xF057E },
        { label: "Bluetooth", glyph: 0xF00AF }
    ]

    Item {
        id: morph
        anchors.fill: parent
        opacity: 0
        scale: 0.78
        transformOrigin: Item.TopRight

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
            anchors.fill: parent
            radius: Theme.popupRadius
            color: Theme.glassBg
            border.color: Theme.glassBorder
            border.width: 1

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
            }
        }
    }
}
