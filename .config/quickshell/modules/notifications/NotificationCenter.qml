import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "../common"

// Notification center — Super+I. A drawer below the bar, top-right on the
// focused monitor: the history the daemon snapshots, rendered as rows in the
// active theme's own notif.qml card chrome, plus a DND toggle and clear-all.
// Themes can dress the panel itself through optional props on the same file:
// panelBg / panelBorder / panelBorderWidth / panelRadius / panelTitle and a
// panelBackdrop Component (its root may declare `property var panel`).
PanelWindow {
    id: root

    required property var store   // the Notifications scope: history/dnd/chrome/pal

    property bool open: false
    property var targetScreen: null
    screen: targetScreen

    WlrLayershell.namespace: "quickshell-notifcenter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || exitTrans.running

    // theme chrome, with glass fallbacks for themes that only dress the cards
    function cp(name, dflt) {
        const c = store.chrome
        return (c && c[name] !== undefined) ? c[name] : dflt
    }

    function openPanel() {
        const m = Hyprland.focusedMonitor
        targetScreen = m ? (Quickshell.screens.find(s => s.name === m.name) ?? null) : null
        open = true
        Qt.callLater(kb.forceActiveFocus)
    }
    function closePanel() { open = false }
    function toggle() { open ? closePanel() : openPanel() }

    // re-evaluates every "x min ago" label while the panel is up
    property int tickRev: 0
    Timer { interval: 30000; repeat: true; running: root.open; onTriggered: root.tickRev++ }
    function ago(ts) {
        void root.tickRev
        const d = Math.max(0, Date.now() - ts)
        if (d < 60000) return "now"
        if (d < 3600000) return Math.floor(d / 60000) + "m"
        if (d < 86400000) return Math.floor(d / 3600000) + "h"
        return Math.floor(d / 86400000) + "d"
    }

    Item {
        id: kb
        focus: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { root.closePanel(); e.accepted = true }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closePanel()
    }

    Item {
        id: morph
        width: panel.width
        height: panel.height
        x: parent.width - width - ((ThemeConfig.barPosition === "right" ? Theme.barHeight : 0) + 12)
        y: (ThemeConfig.barPosition === "top" ? Theme.barHeight : 0) + 12
        opacity: 0
        transform: Translate { id: slide; x: 26 }

        states: State {
            name: "shown"
            when: root.open
            PropertyChanges { target: morph; opacity: 1 }
            PropertyChanges { target: slide; x: 0 }
        }
        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: slide; property: "x"; duration: 240; easing.type: Easing.OutCubic }
                }
            },
            Transition {
                id: exitTrans
                from: "shown"
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "opacity"; duration: 150; easing.type: Easing.InCubic }
                    NumberAnimation { target: slide; property: "x"; to: 26; duration: 150; easing.type: Easing.InCubic }
                }
            }
        ]

        Rectangle {
            id: panel
            width: 380
            height: {
                const maxH = root.height - morph.y - 24
                const content = header.height + dndStrip.height
                    + (root.store.history.length === 0 ? 130 : list.contentHeight + 24)
                return Math.max(170, Math.min(maxH, content))
            }
            radius: root.cp("panelRadius", Theme.cyber ? 3 : Theme.popupRadius)
            color: root.cp("panelBg", Theme.cyber ? Qt.rgba(0.04, 0.04, 0.07, 0.94)
                : Qt.rgba(ThemeConfig.glass.r, ThemeConfig.glass.g, ThemeConfig.glass.b, 0.92))
            border.width: root.cp("panelBorderWidth", 1)
            border.color: root.cp("panelBorder", Theme.cyber ? Theme.neon : Theme.glassBorder)

            readonly property bool dnd: root.store.dnd
            readonly property int count: root.store.history.length

            MouseArea { anchors.fill: parent }   // swallow clicks under the scrim

            // theme chassis behind the content
            Loader {
                anchors.fill: parent
                active: !!(root.store.chrome && root.cp("panelBackdrop", null))
                sourceComponent: active ? root.cp("panelBackdrop", null) : undefined
                onLoaded: if (item && item.hasOwnProperty("panel")) item.panel = panel
            }

            Item {
                id: header
                width: parent.width
                height: 54

                Text {
                    anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                    text: String(root.cp("panelTitle", "Notifications")).toUpperCase()
                    textFormat: Text.PlainText
                    color: Theme.textBright
                    font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 2.5
                }

                Row {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 6

                    // DND pill — crescent fills with accent while quiet hours are on
                    Rectangle {
                        width: dndRow.implicitWidth + 18
                        height: 26
                        radius: Theme.cyber ? 2 : 13
                        color: panel.dnd ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                             : dndMa.containsMouse ? Theme.rowHover : "transparent"
                        border.width: 1
                        border.color: panel.dnd ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) : Theme.divider

                        Row {
                            id: dndRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(0xF0594) // nf-md-weather_night
                                font.family: Theme.icon
                                font.pixelSize: 13
                                color: panel.dnd ? Theme.accent : Theme.textMuted
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "DND"
                                color: panel.dnd ? Theme.accent : Theme.textMuted
                                font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                            }
                        }
                        MouseArea {
                            id: dndMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.store.setDnd(!root.store.dnd)
                        }
                    }

                    // clear-all
                    Rectangle {
                        width: 26; height: 26
                        radius: Theme.cyber ? 2 : 13
                        visible: panel.count > 0
                        color: clearMa.containsMouse ? Theme.dangerHover : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF01B4) // nf-md-delete
                            font.family: Theme.icon
                            font.pixelSize: 14
                            color: clearMa.containsMouse ? Theme.danger : Theme.textMuted
                        }
                        MouseArea {
                            id: clearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.store.clearHistory()
                        }
                    }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 14 }
                    height: 1
                    color: Theme.divider
                }
            }

            // quiet-hours banner under the header while DND is on
            Rectangle {
                id: dndStrip
                anchors.top: header.bottom
                width: parent.width
                height: panel.dnd ? 30 : 0
                visible: panel.dnd
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.07)
                Text {
                    anchors.centerIn: parent
                    text: "Do not disturb — new notifications land here quietly"
                    color: Theme.textMuted
                    font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                    font.pixelSize: 10
                    font.italic: !Theme.cyber
                }
            }

            ListView {
                id: list
                anchors { top: dndStrip.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
                anchors.margins: 12
                anchors.topMargin: 10
                visible: root.store.history.length > 0
                clip: true
                spacing: 8
                model: root.store.history
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var chrome: root.store.chrome
                    readonly property int urgency: modelData.urgency
                    readonly property bool hovered: rowMa.containsMouse
                    readonly property bool sticky: false
                    readonly property color accentCol:
                        urgency === NotificationUrgency.Critical ? Theme.danger
                        : urgency === NotificationUrgency.Low ? Theme.textMuted
                        : Theme.accent

                    width: ListView.view.width
                    implicitHeight: rowCol.implicitHeight + 20
                    radius: chrome ? chrome.cardRadius : (Theme.cyber ? 3 : 14)
                    color: chrome ? chrome.cardBg
                         : Theme.cyber ? Qt.rgba(0.04, 0.04, 0.07, 0.96)
                                       : Qt.rgba(ThemeConfig.glass.r, ThemeConfig.glass.g, ThemeConfig.glass.b, 0.94)
                    border.width: chrome ? chrome.cardBorderWidth : 1
                    border.color: chrome ? chrome.cardBorder
                                : Theme.cyber ? Theme.neon : Theme.glassBorder

                    // same chassis the popup cards mount; the row plays the note
                    Loader {
                        anchors.fill: parent
                        active: !!(row.chrome && row.chrome.backdrop)
                        sourceComponent: active ? row.chrome.backdrop : undefined
                        onLoaded: if (item && item.hasOwnProperty("note")) item.note = row
                    }

                    Rectangle {
                        visible: !(row.chrome && row.chrome.cardSpine === false)
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 3
                        radius: parent.radius
                        color: row.accentCol
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    Column {
                        id: rowCol
                        anchors {
                            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                            leftMargin: 16; rightMargin: 12
                        }
                        spacing: 4

                        Item {
                            width: parent.width
                            height: 15

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 12; height: 12
                                    sourceSize.width: 12; sourceSize.height: 12
                                    smooth: true
                                    visible: status === Image.Ready
                                    source: {
                                        const ai = row.modelData.appIcon || ""
                                        if (!ai || /^(https?|ftp):/i.test(ai)) return ""
                                        return ai.includes("/") ? ai : Quickshell.iconPath(ai, true)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (row.modelData.appName || "Notification").toUpperCase()
                                    textFormat: Text.PlainText
                                    color: row.accentCol
                                    font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !rowMa.containsMouse
                                text: root.ago(row.modelData.ts)
                                color: Theme.textMuted
                                font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                                font.pixelSize: 9
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: rowMa.containsMouse
                                text: String.fromCodePoint(0xF0156) // mdi close
                                font.family: Theme.icon
                                font.pixelSize: 12
                                color: xMa.containsMouse ? Theme.textBright : Theme.textMuted
                                MouseArea {
                                    id: xMa
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.store.removeHistoryAt(row.index)
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: row.modelData.summary
                            textFormat: Text.PlainText
                            color: Theme.textBright
                            font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: (row.modelData.body || "").replace(/<img[^>]*>/gi, "")
                            textFormat: Text.StyledText
                            color: Theme.textMuted
                            font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: 3
                            onLinkActivated: (l) => Qt.openUrlExternally(l)
                        }
                    }
                }
            }

            // empty state
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: (header.height + dndStrip.height) / 2 - 6
                spacing: 8
                visible: root.store.history.length === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String.fromCodePoint(panel.dnd ? 0xF0594 : 0xF009A) // crescent / bell
                    font.family: Theme.icon
                    font.pixelSize: 26
                    color: Theme.textMuted
                    opacity: 0.7
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: panel.dnd ? "Resting quietly" : "All caught up"
                    color: Theme.textMuted
                    font.family: Theme.cyber ? Theme.mono : "Noto Sans"
                    font.pixelSize: 12
                }
            }
        }
    }
}
