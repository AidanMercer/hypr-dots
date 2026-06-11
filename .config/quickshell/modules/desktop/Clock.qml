import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"

// Desktop clock: huge thin stacked HH / mm with a small date above, iOS
// lock-screen style. Vertically centered on the left. Lives on the Bottom
// layer-shell layer — above the wallpaper, below normal windows — and is
// click-through (empty input mask) so it never gets in the way.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-desktop-clock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { left: true; top: true; bottom: true }
    implicitWidth: content.implicitWidth + 88
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {} // empty → clicks pass straight through to the desktop

    readonly property string clockFont: "Adwaita Sans"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.leftMargin: 56
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            color: Theme.textSecondary
            font.family: root.clockFont
            font.pixelSize: 26
            font.weight: Font.Medium
            font.letterSpacing: 3
            bottomPadding: 8
        }

        Text {
            text: Qt.formatDateTime(clock.date, "HH")
            color: Theme.textBright
            font.family: root.clockFont
            font.pixelSize: 150
            font.weight: Font.Normal
            font.letterSpacing: -2
            lineHeight: 0.72
            lineHeightMode: Text.ProportionalHeight
        }

        Text {
            text: Qt.formatDateTime(clock.date, "mm")
            color: Theme.textBright
            font.family: root.clockFont
            font.pixelSize: 150
            font.weight: Font.Normal
            font.letterSpacing: -2
            lineHeight: 0.92
            lineHeightMode: Text.ProportionalHeight
        }
    }
}
