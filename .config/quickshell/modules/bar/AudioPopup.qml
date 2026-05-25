import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../common"

PopupWindow {
    id: root

    property var barWindow
    property real bubbleRight: 0
    property bool open: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volPercent: Math.round(vol * 100)

    anchor.window: barWindow
    anchor.rect.x: bubbleRight - implicitWidth
    anchor.rect.y: barWindow ? barWindow.implicitHeight + 4 : 0
    implicitWidth: 320
    implicitHeight: popupContent.implicitHeight + 32
    visible: open || exitTrans.running
    color: "transparent"

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
                id: popupContent
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Item {
                    width: parent.width
                    height: 32

                    SpeakerIcon {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 17
                        iconColor: root.muted ? Theme.textDim : Theme.textBright
                        muted: root.muted
                        level: root.vol
                        Behavior on iconColor { ColorAnimation { duration: 200 } }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.volPercent + "%"
                        color: root.muted ? Theme.textDim : Theme.textBright
                        font.pixelSize: 24
                        font.family: Theme.mono
                        font.weight: Font.Light
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                Item {
                    id: volSlider
                    width: parent.width
                    height: 18

                    readonly property real fillWidth: track.width * root.vol

                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 6
                        radius: 3
                        color: Theme.trackBg

                        Rectangle {
                            width: volSlider.fillWidth
                            height: parent.height
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: root.muted ? Theme.volGradMuteStart : Theme.volGradStart }
                                GradientStop { position: 1; color: root.muted ? Theme.volGradMuteEnd : Theme.volGradEnd }
                            }
                        }
                    }

                    Rectangle {
                        id: thumb
                        x: volSlider.fillWidth - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.textBright
                        border.color: Theme.thumbBorder
                        border.width: 1
                        scale: sliderMa.pressed ? 1.15 : 1.0
                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        id: sliderMa
                        anchors.fill: parent
                        anchors.topMargin: -6
                        anchors.bottomMargin: -6
                        cursorShape: Qt.PointingHandCursor
                        onPressed: (m) => setVol(m.x)
                        onPositionChanged: (m) => { if (pressed) setVol(m.x) }

                        function setVol(x) {
                            if (!root.sink) return
                            root.sink.audio.volume = Math.max(0, Math.min(1, x / volSlider.width))
                        }
                    }
                }

                component SectionHeader: Item {
                    property string label: ""
                    width: popupContent.width
                    height: 14

                    Text {
                        id: hdrLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.label
                        color: Theme.textDim
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 2
                    }

                    Rectangle {
                        anchors.left: hdrLabel.right
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        height: 1
                        color: Theme.divider
                    }
                }

                component DeviceRow: Rectangle {
                    id: deviceRow
                    property var node
                    property bool isDefault: false
                    signal activated

                    width: popupContent.width
                    height: 34
                    radius: 11
                    color: isDefault
                        ? Theme.rowSelected
                        : (rowMa.containsMouse ? Theme.rowHover : "transparent")
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        id: dot
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: deviceRow.isDefault ? Theme.accent : "transparent"
                        border.width: deviceRow.isDefault ? 0 : 1
                        border.color: Theme.dotBorder
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        anchors.left: dot.right
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: deviceRow.node?.description ?? deviceRow.node?.name ?? ""
                        color: deviceRow.isDefault ? Theme.textBright : Theme.textTertiary
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: deviceRow.activated()
                    }
                }

                SectionHeader { label: "OUTPUT" }

                Repeater {
                    model: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
                    delegate: DeviceRow {
                        required property var modelData
                        node: modelData
                        isDefault: modelData === Pipewire.defaultAudioSink
                        onActivated: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }

                SectionHeader { label: "INPUT" }

                Repeater {
                    model: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
                    delegate: DeviceRow {
                        required property var modelData
                        node: modelData
                        isDefault: modelData === Pipewire.defaultAudioSource
                        onActivated: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }
            }
        }
    }
}
