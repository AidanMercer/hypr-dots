import QtQuick
import Quickshell
import "../common"

// Power / session menu. Anchored under the power button on the right edge.
// Each action is run detached (Quickshell.execDetached) so it survives a
// quickshell reload, which matters for systemctl actions and the locker.
PopupWindow {
    id: root

    property var barWindow
    property real anchorRight: 0
    property bool open: false

    anchor.window: barWindow
    anchor.rect.x: anchorRight - implicitWidth
    anchor.rect.y: barWindow ? barWindow.implicitHeight + 6 : 0
    implicitWidth: 210
    implicitHeight: menuColumn.implicitHeight + 16
    visible: open || exitTrans.running
    color: "transparent"

    // glyph codepoints from Symbols Nerd Font (nf-md-*)
    readonly property var actions: [
        { label: "Lock screen", glyph: 0xF033E, cmd: ["hyprlock"],                  danger: false },
        { label: "Suspend",     glyph: 0xF04B2, cmd: ["systemctl", "suspend"],      danger: false },
        { label: "Log out",     glyph: 0xF0343, cmd: ["hyprctl", "dispatch", "exit"], danger: false },
        { label: "Reboot",      glyph: 0xF0709, cmd: ["systemctl", "reboot"],       danger: true  },
        { label: "Shut down",   glyph: 0xF0425, cmd: ["systemctl", "poweroff"],     danger: true  }
    ]

    function run(cmd) {
        Quickshell.execDetached(cmd)
        root.open = false
    }

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

            Column {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: root.actions

                    delegate: Rectangle {
                        id: actionRow
                        required property var modelData
                        width: menuColumn.width
                        height: 36
                        radius: 11
                        color: rowMa.containsMouse
                            ? (modelData.danger ? Theme.dangerHover : Theme.rowHover)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: rowIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(actionRow.modelData.glyph)
                            font.family: Theme.icon
                            font.pixelSize: 15
                            color: actionRow.modelData.danger
                                ? (rowMa.containsMouse ? Theme.danger : Theme.textSecondary)
                                : (rowMa.containsMouse ? Theme.textBright : Theme.textSecondary)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            anchors.left: rowIcon.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: actionRow.modelData.label
                            font.pixelSize: 13
                            color: actionRow.modelData.danger
                                ? (rowMa.containsMouse ? Theme.danger : Theme.textTertiary)
                                : (rowMa.containsMouse ? Theme.textBright : Theme.textTertiary)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.run(actionRow.modelData.cmd)
                        }
                    }
                }
            }
        }
    }
}
