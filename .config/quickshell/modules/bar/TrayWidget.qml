import QtQuick
import Quickshell.Services.SystemTray
import "../common"

// System tray, sat just left of the resource readout. One icon per StatusNotifier
// item: left-click activates (usually toggles the app window), middle-click is the
// secondary action, right-click opens the app's own native menu via display().
// Collapses to zero width when the tray is empty so the bar stays clean.
//
// `barWindow` is the bar's PanelWindow — display() needs a parent window to anchor
// the menu, and we map the click into its coordinates so the menu drops under the icon.
Item {
    id: root
    height: Theme.bubbleHeight
    width: SystemTray.items.values.length > 0 ? row.width : 0
    visible: width > 0

    required property var barWindow

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: SystemTray.items.values

            delegate: Rectangle {
                id: cell
                required property var modelData
                width: 26
                height: 26
                radius: 7
                color: cellMa.containsMouse ? Theme.rowHover : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Image {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    sourceSize.width: 17
                    sourceSize.height: 17
                    smooth: true
                    source: cell.modelData.icon
                    visible: status === Image.Ready
                }

                // fallback glyph when an item ships no usable icon
                Text {
                    anchors.centerIn: parent
                    visible: cell.modelData.icon === ""
                    text: String.fromCodePoint(0xF0C90) // mdi puzzle
                    font.family: Theme.icon
                    font.pixelSize: 13
                    color: Theme.textMuted
                }

                MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: (mouse) => {
                        const it = cell.modelData
                        if (mouse.button === Qt.LeftButton) {
                            if (it.onlyMenu) root.openMenu(cell, it)
                            else it.activate()
                        } else if (mouse.button === Qt.MiddleButton) {
                            it.secondaryActivate()
                        } else if (mouse.button === Qt.RightButton) {
                            root.openMenu(cell, it)
                        }
                    }
                }
            }
        }
    }

    // Drop the app's native menu just under its icon.
    function openMenu(cell, item) {
        if (!item.hasMenu) return
        const p = cell.mapToItem(null, cell.width / 2, cell.height)
        item.display(root.barWindow, p.x, p.y)
    }
}
