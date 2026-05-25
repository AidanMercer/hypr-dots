import QtQuick
import Quickshell.Services.Pipewire
import "../common"

Bubble {
    id: root
    width: audioRow.width + 22

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volPercent: Math.round(vol * 100)

    signal popupToggleRequested()

    Row {
        id: audioRow
        anchors.centerIn: parent
        spacing: 6

        SpeakerIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconColor: Theme.textPrimary
            muted: root.muted
            level: root.vol
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.volPercent + "%"
            color: Theme.textPrimary
            font.pixelSize: 13
            font.family: Theme.mono
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                if (root.sink) root.sink.audio.muted = !root.sink.audio.muted
            } else {
                root.popupToggleRequested()
            }
        }

        onWheel: function(wheel) {
            if (!root.sink) return
            const step = 0.05
            const cur = root.sink.audio.volume
            root.sink.audio.volume = wheel.angleDelta.y > 0
                ? Math.min(1, cur + step)
                : Math.max(0, cur - step)
        }
    }
}
