import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"

// Desktop clock: a stacked HH / mm with a small date, vertically centered on
// the left. Lives on the Bottom layer-shell layer — above the wallpaper, below
// normal windows — and is click-through (empty input mask) so it never gets in
// the way of anything on the desktop.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-desktop-clock"

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { left: true; top: true; bottom: true }
    implicitWidth: content.implicitWidth + 96
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {} // empty → clicks pass straight through to the desktop

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
            text: Qt.formatDateTime(clock.date, "HH")
            color: Theme.textBright
            font.family: Theme.mono
            font.pixelSize: 96
            font.weight: Font.DemiBold
            font.letterSpacing: -2
            lineHeight: 0.86
            lineHeightMode: Text.ProportionalHeight
        }

        Text {
            text: Qt.formatDateTime(clock.date, "mm")
            color: Theme.accent
            font.family: Theme.mono
            font.pixelSize: 96
            font.weight: Font.DemiBold
            font.letterSpacing: -2
            lineHeight: 0.86
            lineHeightMode: Text.ProportionalHeight
        }

        Item { width: 1; height: 16 }

        Text {
            text: Qt.formatDateTime(clock.date, "ddd, MMM d").toLowerCase()
            color: Theme.textMuted
            font.family: Theme.mono
            font.pixelSize: 17
            font.letterSpacing: 1
        }
    }
}
