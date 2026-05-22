import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire

ShellRoot {
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell-bar"

            anchors {
                top: true
                left: true
                right: true
            }
            height: 44
            color: "transparent"

            component Bubble: Rectangle {
                height: 32
                radius: 16
                color: Qt.rgba(0.1, 0.1, 0.14, 0.22)
                border.color: Qt.rgba(1, 1, 1, 0.18)
                border.width: 1
            }

            Bubble {
                id: dateBubble
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: dateRow.width + 24

                Row {
                    id: dateRow
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: "#e6e6f0"
                        font.pixelSize: 14
                        font.family: "monospace"
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 14
                        color: Qt.rgba(1, 1, 1, 0.15)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "ddd, MMM d")
                        color: "#a8a8b8"
                        font.pixelSize: 13
                    }
                }
            }

            Bubble {
                id: wsBubble
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: wsRow.width + 10

                readonly property int wsPerPage: 5
                readonly property int focusedWsId: Hyprland.focusedWorkspace?.id ?? 1
                readonly property int wsPageStart: Math.floor((focusedWsId - 1) / wsPerPage) * wsPerPage + 1
                readonly property int activeIndex: focusedWsId - wsPageStart
                readonly property int pillWidth: 26
                readonly property int pillSpacing: 4

                Rectangle {
                    id: activeIndicator
                    width: wsBubble.pillWidth
                    height: 22
                    radius: 11
                    anchors.verticalCenter: parent.verticalCenter
                    x: wsRow.x + wsBubble.activeIndex * (wsBubble.pillWidth + wsBubble.pillSpacing)
                    color: Qt.rgba(0.1, 0.1, 0.14, 0.22)
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    border.width: 1

                    Behavior on x {
                        SpringAnimation { spring: 2.6; damping: 0.28; epsilon: 0.1 }
                    }
                }

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: wsBubble.pillSpacing

                    Repeater {
                        model: wsBubble.wsPerPage

                        delegate: Rectangle {
                            id: wsItem
                            required property int index
                            readonly property int wsId: wsBubble.wsPageStart + index
                            readonly property bool isActive: Hyprland.focusedWorkspace?.id === wsId
                            readonly property bool isOccupied: Hyprland.workspaces.values.some(ws => ws.id === wsId)

                            width: wsBubble.pillWidth
                            height: 22
                            radius: 11
                            color: !isActive && isOccupied
                                ? Qt.rgba(1, 1, 1, 0.08)
                                : "transparent"

                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: wsItem.wsId
                                color: wsItem.isActive
                                    ? "#ffffff"
                                    : (wsItem.isOccupied ? "#e6e6f0" : "#6a6a78")
                                font.pixelSize: 11
                                font.weight: Font.Bold

                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch(`workspace ${wsItem.wsId}`)
                            }
                        }
                    }
                }
            }

            Bubble {
                id: audioBubble
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: audioRow.width + 22

                readonly property var sink: Pipewire.defaultAudioSink
                readonly property real vol: sink?.audio?.volume ?? 0
                readonly property bool muted: sink?.audio?.muted ?? false
                readonly property int volPercent: Math.round(vol * 100)

                Row {
                    id: audioRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: audioBubble.muted ? "🔇"
                            : audioBubble.volPercent > 66 ? "🔊"
                            : audioBubble.volPercent > 33 ? "🔉"
                            : audioBubble.volPercent > 0  ? "🔈"
                            : "🔇"
                        color: "#e6e6f0"
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: audioBubble.volPercent + "%"
                        color: "#e6e6f0"
                        font.pixelSize: 13
                        font.family: "monospace"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            if (audioBubble.sink) audioBubble.sink.audio.muted = !audioBubble.sink.audio.muted
                        } else {
                            audioPopup.visible = !audioPopup.visible
                        }
                    }

                    onWheel: function(wheel) {
                        if (!audioBubble.sink) return
                        const step = 0.05
                        const cur = audioBubble.sink.audio.volume
                        audioBubble.sink.audio.volume = wheel.angleDelta.y > 0
                            ? Math.min(1, cur + step)
                            : Math.max(0, cur - step)
                    }
                }
            }

            PopupWindow {
                id: audioPopup
                anchor.window: bar
                anchor.rect.x: bar.width - width - 10
                anchor.rect.y: bar.height + 2
                width: 300
                height: popupContent.implicitHeight + 24
                visible: false
                color: "transparent"

                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: Qt.rgba(0.08, 0.08, 0.11, 0.92)
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    border.width: 1

                    Column {
                        id: popupContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Row {
                            width: parent.width
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: audioBubble.muted ? "🔇" : "🔊"
                                font.pixelSize: 16
                                color: "#e6e6f0"
                            }

                            Item {
                                id: volSlider
                                width: parent.width - 80
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.15)

                                    Rectangle {
                                        width: parent.width * audioBubble.vol
                                        height: parent.height
                                        radius: 2
                                        color: audioBubble.muted ? "#666" : "#a8b5e8"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (m) => setVol(m.x)
                                    onPositionChanged: (m) => { if (pressed) setVol(m.x) }

                                    function setVol(x) {
                                        if (!audioBubble.sink) return
                                        audioBubble.sink.audio.volume = Math.max(0, Math.min(1, x / width))
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: audioBubble.volPercent + "%"
                                color: "#e6e6f0"
                                font.pixelSize: 12
                                font.family: "monospace"
                                width: 38
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        Text {
                            text: "OUTPUT"
                            color: "#8a8a98"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                        }

                        Repeater {
                            model: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)

                            delegate: Rectangle {
                                id: outItem
                                required property var modelData
                                readonly property bool isDefault: modelData === Pipewire.defaultAudioSink

                                width: popupContent.width
                                height: 26
                                radius: 8
                                color: isDefault ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: outItem.modelData.description ?? outItem.modelData.name ?? ""
                                    color: outItem.isDefault ? "#ffffff" : "#c0c0c8"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Pipewire.preferredDefaultAudioSink = outItem.modelData
                                }
                            }
                        }

                        Text {
                            text: "INPUT"
                            color: "#8a8a98"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                        }

                        Repeater {
                            model: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)

                            delegate: Rectangle {
                                id: inItem
                                required property var modelData
                                readonly property bool isDefault: modelData === Pipewire.defaultAudioSource

                                width: popupContent.width
                                height: 26
                                radius: 8
                                color: isDefault ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: inItem.modelData.description ?? inItem.modelData.name ?? ""
                                    color: inItem.isDefault ? "#ffffff" : "#c0c0c8"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Pipewire.preferredDefaultAudioSource = inItem.modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
