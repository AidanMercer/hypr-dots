import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../common"

// Fullscreen, transparent layer-shell overlay. The launcher card is centred
// inside it; clicking the surrounding scrim (or pressing Esc) dismisses it.
// Opened/closed over IPC: `qs ipc call launcher toggle` (wired to Super in
// hyprland.conf).
PanelWindow {
    id: root

    property bool open: false
    // The monitor the launcher should appear on. Captured at open() time so a
    // wandering cursor (follow_mouse) can't remap the window mid-use.
    property var targetScreen: null
    screen: targetScreen

    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Grab the keyboard only while open, so typing goes to the search box and
    // other windows keep their focus the rest of the time.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    // Ignore the bar's exclusive zone so the scrim covers the full output,
    // including the strip under the bar (otherwise the top 44px stays bright).
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Stay mapped during the close animation, mirroring the popups.
    visible: open || exitTrans.running

    // ---- data ----------------------------------------------------------
    property string query: ""
    property int selectedIndex: 0
    // Reading DesktopEntries.applications in a live binding keeps the (lazy)
    // service populated; .values is the plain JS array of entries.
    readonly property var allApps: DesktopEntries.applications.values
    property var results: filterApps(query, allApps)

    function filterApps(q, apps) {
        const list = (apps || []).filter(a => a && a.name && !a.noDisplay)
        if (!q)
            return list.slice().sort((a, b) => a.name.localeCompare(b.name))
        const ql = q.toLowerCase()
        return list
            .filter(a => a.name.toLowerCase().includes(ql))
            .sort((a, b) => {
                // Prefix matches rank above mid-string matches.
                const ar = a.name.toLowerCase().startsWith(ql) ? 0 : 1
                const br = b.name.toLowerCase().startsWith(ql) ? 0 : 1
                if (ar !== br) return ar - br
                return a.name.localeCompare(b.name)
            })
    }

    function openMenu() {
        const m = Hyprland.focusedMonitor
        targetScreen = m ? (Quickshell.screens.find(s => s.name === m.name) ?? null) : null
        searchInput.text = ""   // resets query + selection via onTextChanged
        selectedIndex = 0
        open = true
        Qt.callLater(searchInput.forceActiveFocus)
    }
    function closeMenu() { open = false }
    function launch(entry) {
        if (!entry) return
        entry.execute()
        closeMenu()
    }
    function moveSel(delta) {
        if (results.length === 0) return
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta))
    }

    IpcHandler {
        target: "launcher"
        // Only `toggle` is wired to a key (Super tap / Super+R in hyprland.conf).
        function toggle(): void { root.open ? root.closeMenu() : root.openMenu() }
    }

    // ---- scrim (click-outside to dismiss) ------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.28)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeMenu()
        }
    }

    // ---- the glass card ------------------------------------------------
    Item {
        id: morph
        width: card.width
        height: card.height
        x: (parent.width - width) / 2
        y: parent.height * 0.16
        opacity: 0
        scale: 0.92
        transformOrigin: Item.Top

        states: State {
            name: "shown"
            when: root.open
            PropertyChanges { target: morph; opacity: 1; scale: 1 }
        }

        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                    SpringAnimation { property: "scale"; spring: 3; damping: 0.34; epsilon: 0.001 }
                }
            },
            Transition {
                id: exitTrans
                from: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 160; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; duration: 160; easing.type: Easing.InCubic }
                }
            }
        ]

        Rectangle {
            id: card
            width: 480
            height: cardCol.height + 24
            radius: Theme.popupRadius
            color: Theme.glassBg
            border.color: Theme.glassBorder
            border.width: 1

            // Swallow clicks that land on the card background so they don't
            // fall through to the scrim and close the launcher.
            MouseArea { anchors.fill: parent }

            // Thin highlight along the top edge, same as the popups.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: parent.radius
                anchors.rightMargin: parent.radius
                anchors.topMargin: 1
                height: 1
                color: Theme.glassHighlight
            }

            Column {
                id: cardCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                // search row
                Item {
                    width: parent.width
                    height: 38

                    Text {
                        id: searchGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF0349) // nf-md-magnify
                        font.family: Theme.icon
                        font.pixelSize: 18
                        color: Theme.textSecondary
                    }

                    TextInput {
                        id: searchInput
                        anchors.left: searchGlyph.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.textBright
                        font.pixelSize: 16
                        selectionColor: Theme.accent
                        selectedTextColor: "#1a1a22"
                        clip: true
                        focus: true

                        onTextChanged: {
                            root.query = text
                            root.selectedIndex = 0
                        }

                        Keys.onPressed: (e) => {
                            if (e.key === Qt.Key_Down) { root.moveSel(1); e.accepted = true }
                            else if (e.key === Qt.Key_Up) { root.moveSel(-1); e.accepted = true }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                root.launch(root.results[root.selectedIndex]); e.accepted = true
                            } else if (e.key === Qt.Key_Escape) {
                                root.closeMenu(); e.accepted = true
                            }
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Search apps…"
                            color: Theme.textMuted
                            font: searchInput.font
                            visible: searchInput.text.length === 0
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.divider
                }

                // app list
                ListView {
                    id: list
                    width: parent.width
                    height: Math.min(root.results.length, 7) * 42
                    clip: true
                    model: root.results
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 42
                        radius: 11
                        color: ListView.isCurrentItem
                            ? Theme.rowSelected
                            : (rowMa.containsMouse ? Theme.rowHover : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Rectangle {
                            id: dot
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: appRow.ListView.isCurrentItem ? Theme.accent : "transparent"
                            border.width: appRow.ListView.isCurrentItem ? 0 : 1
                            border.color: Theme.dotBorder
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            anchors.left: dot.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: appRow.modelData.name
                            color: appRow.ListView.isCurrentItem ? Theme.textBright : Theme.textTertiary
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = appRow.index
                            onClicked: root.launch(appRow.modelData)
                        }
                    }
                }

                Text {
                    visible: root.results.length === 0
                    width: parent.width
                    text: root.query.length ? "No matches" : "No applications"
                    color: Theme.textMuted
                    font.pixelSize: 13
                    font.italic: true
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 6
                    bottomPadding: 6
                }
            }
        }
    }
}
