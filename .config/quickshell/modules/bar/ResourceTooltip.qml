import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"

// Small frosted card that appears just below the ResourceBubble when it's
// hovered, showing the breakdown behind the bare percentages:
//   • CPU — current %, load averages (1 / 5 / 15 min), and core count
//   • RAM — current %, and used / total in GB
//
// Implemented as a separate top-right layer-shell window (no scrim, no
// keyboard focus, click-through where there's no card), mirroring the
// existing ControlPopup pattern but stripped down.
PanelWindow {
    id: root

    property var barWindow
    property int anchorRightMargin: 10   // matches ResourceBubble's rightMargin
    property bool open: false            // bound from ResourceBubble.hovered

    // Data piped in from the bubble.
    property int cpuPercent: -1
    property int ramPercent: -1
    property real load1: 0
    property real load5: 0
    property real load15: 0
    property int cpuCores: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0

    screen: barWindow ? barWindow.screen : null

    WlrLayershell.namespace: "quickshell-resource-tooltip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Anchor only top+right so the surface is just big enough to hold the
    // card — the rest of the screen stays click-through.
    anchors { top: true; right: true }
    margins.top: Theme.barHeight + 4
    margins.right: anchorRightMargin

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: card.width
    implicitHeight: card.height
    // Stay mapped through the exit animation, then unmap.
    visible: open || exitTrans.running

    function fmt(v) { return v < 0 ? "—" : v + "%" }
    function gb(g)  { return g.toFixed(1) }

    Rectangle {
        id: card
        width: 220
        height: content.implicitHeight + 24
        radius: Theme.popupRadius
        color: Theme.glassBg
        border.color: Theme.glassBorder
        border.width: 1
        opacity: 0
        scale: 0.94
        transformOrigin: Item.TopRight

        states: State {
            name: "shown"
            when: root.open
            PropertyChanges { target: card; opacity: 1; scale: 1 }
        }

        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; duration: 160; easing.type: Easing.OutCubic }
                }
            },
            Transition {
                id: exitTrans
                from: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 140; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; duration: 140; easing.type: Easing.InCubic }
                }
            }
        ]

        // Subtle inner top highlight, like ControlPopup.
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
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ── CPU section ──
            Column {
                width: parent.width
                spacing: 3

                Row {
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF0EE0)  // nf-md-cpu_64_bit
                        font.family: Theme.icon
                        font.pixelSize: 13
                        color: Theme.textSecondary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CPU"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fmt(root.cpuPercent)
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.mono
                        font.weight: Font.Medium
                    }
                }
                Text {
                    text: "load " + root.load1.toFixed(2) + "  " + root.load5.toFixed(2) + "  " + root.load15.toFixed(2)
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.mono
                    leftPadding: 21
                }
                Text {
                    visible: root.cpuCores > 0
                    text: root.cpuCores + " cores"
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.mono
                    leftPadding: 21
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.divider }

            // ── RAM section ──
            Column {
                width: parent.width
                spacing: 3

                Row {
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF035B)  // nf-md-memory
                        font.family: Theme.icon
                        font.pixelSize: 13
                        color: Theme.textSecondary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RAM"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fmt(root.ramPercent)
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.mono
                        font.weight: Font.Medium
                    }
                }
                Text {
                    visible: root.ramTotalGb > 0
                    text: root.gb(root.ramUsedGb) + " / " + root.gb(root.ramTotalGb) + " GB"
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.mono
                    leftPadding: 21
                }
            }
        }
    }
}
