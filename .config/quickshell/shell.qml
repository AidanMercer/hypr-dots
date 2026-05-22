import QtQuick
import Quickshell

ShellRoot {
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            height: 32
            color: "transparent"

            Text {
                anchors.centerIn: parent
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: "white"
                font.pixelSize: 14
                font.family: "monospace"
            }
        }
    }
}
