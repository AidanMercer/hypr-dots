import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import "../common"

// One combined status pill replacing the old separate network + sound bubbles.
// It shows network state, volume, and (when present) a Bluetooth indicator.
// Clicking it opens the tabbed ControlPopup. It still owns the lightweight
// network status poll (nmcli device status) that drives the network icon; the
// heavier wifi scan lives in the popup's Network tab while it is open.
Bubble {
    id: root
    width: controlRow.width + 24

    // --- network state (polled) ---
    property string connType: "none"   // "wifi" | "ethernet" | "none"
    property string connName: ""

    // --- audio state ---
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volPercent: Math.round(vol * 100)

    // --- bluetooth state (null adapter == stack not running) ---
    readonly property bool btReady: Bluetooth.defaultAdapter !== null
    readonly property bool btConnected: btReady
        && (Bluetooth.devices?.values ?? []).some(d => d.connected)

    // Symbols Nerd Font glyph codepoints
    readonly property string iconWifi: String.fromCodePoint(0xF05A9)      // nf-md-wifi
    readonly property string iconEthernet: String.fromCodePoint(0xF0200)  // nf-md-ethernet
    readonly property string iconOffline: String.fromCodePoint(0xF05AA)   // nf-md-wifi_off
    readonly property string iconBt: String.fromCodePoint(0xF00B1)        // nf-md-bluetooth-connect

    signal popupToggleRequested()

    function refresh() {
        netProc.running = true
    }

    function parseNm(raw) {
        let nextType = "none"
        let nextName = ""
        for (const line of raw.trim().split("\n")) {
            if (!line) continue
            const parts = line.split(":")
            const type = parts[0]
            const state = parts[1]
            const name = parts.slice(2).join(":")
            if (type === "loopback") continue
            if (state !== "connected") continue
            if (type === "wifi") {
                nextType = "wifi"
                nextName = name
                break
            }
            if (type === "ethernet" && nextType === "none") {
                nextType = "ethernet"
                nextName = name
            }
        }
        connType = nextType
        connName = nextName
    }

    Row {
        id: controlRow
        anchors.centerIn: parent
        spacing: 8

        // network
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.connType === "wifi" ? root.iconWifi
                : root.connType === "ethernet" ? root.iconEthernet
                : root.iconOffline
            color: Theme.textPrimary
            font.family: Theme.icon
            font.pixelSize: 15
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.connType === "wifi" ? root.connName
                : root.connType === "ethernet" ? "Ethernet"
                : "Offline"
            color: Theme.textPrimary
            font.pixelSize: 13
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 120)
        }

        // bluetooth indicator (only when a device is connected)
        Text {
            visible: root.btConnected
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconBt
            color: Theme.accent
            font.family: Theme.icon
            font.pixelSize: 14
        }

        // divider
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            color: Theme.subtleDivider
        }

        // sound
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

    // Lightweight, frequent poll of connection status for the icon/label.
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseNm(text)
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: netProc.running = true
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // Left-click opens the popup; right-click mutes; wheel adjusts volume.
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
