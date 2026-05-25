import QtQuick
import Quickshell
import "../common"

Bubble {
    id: root
    width: dateRow.width + 24

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: dateRow
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.textPrimary
            font.pixelSize: 14
            font.family: Theme.mono
            font.weight: Font.Medium
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            color: Theme.subtleDivider
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "ddd, MMM d")
            color: Theme.textSecondary
            font.pixelSize: 13
        }
    }
}
