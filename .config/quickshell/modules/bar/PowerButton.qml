import QtQuick
import "../common"

// Small square glass button on the far right that opens the power menu.
Bubble {
    id: root
    width: Theme.bubbleHeight

    property bool active: false
    signal toggleRequested()

    readonly property string iconPower: String.fromCodePoint(0xF0425) // nf-md-power

    // Tint while the menu is open or hovered so it reads as "armed".
    color: active || ma.containsMouse ? Theme.dangerHover : Theme.glassBg
    Behavior on color { ColorAnimation { duration: 150 } }

    Text {
        anchors.centerIn: parent
        text: root.iconPower
        font.family: Theme.icon
        font.pixelSize: 17
        color: root.active || ma.containsMouse ? Theme.danger : Theme.textPrimary
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleRequested()
    }
}
