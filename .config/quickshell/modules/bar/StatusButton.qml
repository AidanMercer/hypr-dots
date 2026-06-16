import QtQuick
import "../common"

// The single status button: a bare Arch glyph that sits just right of the
// workspaces. Clicking it toggles the ControlPopup (network / sound / bluetooth /
// power / display) via ControlBus. The popup lives in shell.qml now and owns its
// own uptime/network state, so this is just the trigger + glyph.
Item {
    id: root
    width: Theme.bubbleHeight
    height: Theme.bubbleHeight

    property bool active: false
    signal popupToggleRequested()

    readonly property string iconArch: String.fromCodePoint(0xF303) // nf-linux-archlinux

    // kept so the old call site (BarContent) doesn't break; nothing to refresh now.
    function refresh() {}

    // Brighten the glyph while the popup is open or the button is hovered.
    Text {
        anchors.centerIn: parent
        text: root.iconArch
        color: Theme.accent
        font.family: Theme.icon
        font.pixelSize: 15
        opacity: root.active || ma.containsMouse ? 1.0 : 0.75
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.popupToggleRequested()
    }
}
