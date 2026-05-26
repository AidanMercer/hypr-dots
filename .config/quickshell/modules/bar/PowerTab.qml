import QtQuick
import Quickshell
import "../common"

// Power tab: the session actions that used to live in the standalone PowerMenu.
// Self-sizing Item (height follows the inner column) so the popup resizes to it
// like the other tabs. Each command runs detached (Quickshell.execDetached) so
// it survives a quickshell reload — important for systemctl actions and the
// locker. After launching, it emits actionTriggered() so the popup can close.
Item {
    id: root
    implicitHeight: col.implicitHeight

    signal actionTriggered()

    // Keyboard navigation, driven by ControlPopup's Up/Down/Enter. navIndex is
    // the highlighted action (-1 = none); activateNav runs it.
    property int navIndex: -1
    readonly property int navCount: actions.length
    function activateNav() { run(actions[navIndex].cmd) }

    // glyph codepoints from Symbols Nerd Font (nf-md-*)
    readonly property var actions: [
        { label: "Lock screen", glyph: 0xF033E, cmd: ["hyprlock"],                    danger: false },
        { label: "Suspend",     glyph: 0xF04B2, cmd: ["systemctl", "suspend"],        danger: false },
        { label: "Log out",     glyph: 0xF0343, cmd: ["hyprctl", "dispatch", "exit"], danger: false },
        { label: "Reboot",      glyph: 0xF0709, cmd: ["systemctl", "reboot"],         danger: true  },
        { label: "Shut down",   glyph: 0xF0425, cmd: ["systemctl", "poweroff"],       danger: true  }
    ]

    function run(cmd) {
        Quickshell.execDetached(cmd)
        root.actionTriggered()
    }

    Column {
        id: col
        width: parent.width
        spacing: 2

        Repeater {
            model: root.actions

            delegate: Rectangle {
                id: actionRow
                required property var modelData
                required property int index
                // highlit = highlighted by either mouse hover or keyboard nav, so
                // both routes light the row (and its icon/label) the same way.
                readonly property bool highlit: rowMa.containsMouse || root.navIndex === index
                width: col.width
                height: 36
                radius: 11
                color: highlit
                    ? (modelData.danger ? Theme.dangerHover : Theme.rowHover)
                    : "transparent"
                // accent ring marks the keyboard-highlighted row (mouse hover uses
                // background only, so the two are still distinguishable).
                border.width: root.navIndex === index ? 1 : 0
                border.color: Theme.accent
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
                        ? (actionRow.highlit ? Theme.danger : Theme.textSecondary)
                        : (actionRow.highlit ? Theme.textBright : Theme.textSecondary)
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: actionRow.modelData.label
                    font.pixelSize: 13
                    color: actionRow.modelData.danger
                        ? (actionRow.highlit ? Theme.danger : Theme.textTertiary)
                        : (actionRow.highlit ? Theme.textBright : Theme.textTertiary)
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
