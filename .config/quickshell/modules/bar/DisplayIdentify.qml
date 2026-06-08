import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"

// Big white "this is the screen you're holding" badge, shown on a physical
// monitor while its box is dragged in the Display tab. One instance per screen
// (Variants in shell.qml); it lights up when ControlBus.identifyMonitor names
// this screen. Fully click-through (empty input mask) so it never steals the
// drag pointer on the focused monitor.
PanelWindow {
    id: idWin
    required property var modelData
    screen: modelData

    readonly property string monName: screen ? screen.name : ""
    readonly property bool shown: ControlBus.identifyMonitor !== "" && ControlBus.identifyMonitor === monName

    WlrLayershell.namespace: "quickshell-display-identify"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}   // click-through: never intercept the drag pointer
    visible: shown || badge.opacity > 0.01

    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: Math.max(220, idWin.monName.length * 30 + 60)
        height: 150
        radius: 30
        color: Qt.rgba(1, 1, 1, 0.92)
        border.color: Qt.rgba(1, 1, 1, 0.6)
        border.width: 2

        opacity: idWin.shown ? 1 : 0
        scale: idWin.shown ? 1 : 0.88
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

        Column {
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: idWin.monName
                color: "#1a1b26"
                font.pixelSize: 46
                font.weight: Font.Bold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: idWin.screen ? idWin.screen.width + " × " + idWin.screen.height : ""
                color: "#555a6e"
                font.pixelSize: 15
            }
        }
    }
}
