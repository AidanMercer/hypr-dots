import QtQuick
import Quickshell.Hyprland
import "../common"

Bubble {
    id: root
    width: wsRow.width + 10

    readonly property int wsPerPage: 5
    readonly property int focusedWsId: Hyprland.focusedWorkspace?.id ?? 1
    readonly property int wsPageStart: Math.floor((focusedWsId - 1) / wsPerPage) * wsPerPage + 1
    readonly property int activeIndex: focusedWsId - wsPageStart
    readonly property int pillWidth: 26
    readonly property int pillSpacing: 4

    Rectangle {
        id: activeIndicator
        width: root.pillWidth
        height: 22
        radius: 11
        anchors.verticalCenter: parent.verticalCenter
        x: wsRow.x + root.activeIndex * (root.pillWidth + root.pillSpacing)
        color: Theme.glassBg
        border.color: Theme.glassBorder
        border.width: 1

        Behavior on x {
            SpringAnimation { spring: 2.6; damping: 0.28; epsilon: 0.1 }
        }
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: root.pillSpacing

        Repeater {
            model: root.wsPerPage

            delegate: Rectangle {
                id: wsItem
                required property int index
                readonly property int wsId: root.wsPageStart + index
                readonly property bool isActive: Hyprland.focusedWorkspace?.id === wsId
                readonly property bool isOccupied: Hyprland.workspaces.values.some(ws => ws.id === wsId)

                width: root.pillWidth
                height: 22
                radius: 11
                color: !isActive && isOccupied
                    ? Theme.occupiedFill
                    : "transparent"

                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: wsItem.wsId
                    color: wsItem.isActive
                        ? Theme.textBright
                        : (wsItem.isOccupied ? Theme.textPrimary : Theme.textMuted)
                    font.pixelSize: 11
                    font.weight: Font.Bold

                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch(`workspace ${wsItem.wsId}`)
                }
            }
        }
    }
}
