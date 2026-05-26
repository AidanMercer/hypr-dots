import QtQuick
import Quickshell.Services.Pipewire
import "../common"

// Sound tab: master volume slider + output/input device pickers.
// Self-sizing Item — its height follows the inner column so the popup can
// resize to whichever tab is active.
Item {
    id: root
    implicitHeight: col.implicitHeight

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volPercent: Math.round(vol * 100)

    // Output then input device lists, shared by the two Repeaters and keyboard
    // navigation so the indices line up. The volume slider stays mouse-only.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)

    // Keyboard navigation, driven by ControlPopup's Up/Down/Enter. navIndex runs
    // across outputs (0 … sinks-1) then inputs (sinks … end); activateNav makes
    // the highlighted device the default sink or source.
    property int navIndex: -1
    readonly property int navCount: sinks.length + sources.length
    function activateNav() {
        if (navIndex < sinks.length) Pipewire.preferredDefaultAudioSink = sinks[navIndex]
        else Pipewire.preferredDefaultAudioSource = sources[navIndex - sinks.length]
    }

    Column {
        id: col
        width: parent.width
        spacing: 14

        // ── volume readout ──
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

        // ── volume slider ──
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
            width: col.width
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
            property bool navSelected: false
            signal activated

            width: col.width
            height: 34
            radius: 11
            color: isDefault
                ? Theme.rowSelected
                : ((navSelected || rowMa.containsMouse) ? Theme.rowHover : "transparent")
            // accent ring marks the keyboard-highlighted row.
            border.width: navSelected ? 1 : 0
            border.color: Theme.accent
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
            model: root.sinks
            delegate: DeviceRow {
                required property var modelData
                required property int index
                node: modelData
                isDefault: modelData === Pipewire.defaultAudioSink
                navSelected: root.navIndex === index
                onActivated: Pipewire.preferredDefaultAudioSink = modelData
            }
        }

        SectionHeader { label: "INPUT" }

        Repeater {
            model: root.sources
            delegate: DeviceRow {
                required property var modelData
                required property int index
                node: modelData
                isDefault: modelData === Pipewire.defaultAudioSource
                navSelected: root.navIndex === root.sinks.length + index
                onActivated: Pipewire.preferredDefaultAudioSource = modelData
            }
        }
    }
}
