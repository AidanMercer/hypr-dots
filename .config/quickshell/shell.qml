import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            property var modelData
            screen: modelData

            // Lets Hyprland target this surface, e.g. `layerrule = blur, quickshell:bar`
            WlrLayershell.namespace: "quickshell:bar"

            anchors {
                top: true
                left: true
                right: true
            }
            height: 44
            color: "transparent"

            Rectangle {
                id: panel
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 6
                anchors.bottomMargin: 4
                radius: 16
                color: Qt.rgba(0.07, 0.08, 0.12, 0.55)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: parent.radius
                    anchors.rightMargin: parent.radius
                    anchors.topMargin: 1
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.10)
                }
            }

            Item {
                anchors.fill: panel
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Repeater {
                        model: 5

                        delegate: Rectangle {
                            required property int index
                            readonly property int wsId: index + 1
                            readonly property bool isActive: Hyprland.focusedWorkspace?.id === wsId
                            readonly property bool isOccupied: Hyprland.workspaces.values.some(ws => ws.id === wsId)

                            width: isActive ? 26 : 10
                            height: 10
                            radius: 5
                            color: isActive
                                ? "#a8b5e8"
                                : (isOccupied ? "#5a6285" : Qt.rgba(1, 1, 1, 0.12))

                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation  { duration: 220 } }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch(`workspace ${parent.wsId}`)
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: "#e6e6f0"
                    font.pixelSize: 15
                    font.family: "monospace"
                    font.weight: Font.Medium
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(clock.date, "ddd, MMM d")
                    color: "#a8a8b8"
                    font.pixelSize: 13
                }
            }
        }
    }
}
