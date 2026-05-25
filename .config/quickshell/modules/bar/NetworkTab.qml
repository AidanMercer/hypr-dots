import QtQuick
import Quickshell.Io
import "../common"

// Network tab: shows the active connection and a scannable wifi list.
// `connType`/`connName` are fed in from StatusButton (the always-on poll);
// the wifi rescan only runs while `active` (this tab visible + popup open) to
// avoid burning radio scans in the background.
//
// The wifi list is a fixed-height ListView so the tab (and therefore the
// popup) stays the same size no matter how many networks are in range — you
// scroll the list instead of growing the window.
Item {
    id: root
    implicitHeight: col.implicitHeight

    property string connType: "none"
    property string connName: ""
    property bool active: false
    property var networks: []

    // height of the scrollable wifi area (≈ 5 rows); keep this constant
    readonly property int listHeight: 172

    signal connectionChanged()

    onActiveChanged: if (active) wifiListProc.running = true

    function splitNm(line) {
        const parts = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            if (line[i] === "\\" && line[i + 1] === ":") {
                cur += ":"
                i++
            } else if (line[i] === ":") {
                parts.push(cur)
                cur = ""
            } else {
                cur += line[i]
            }
        }
        parts.push(cur)
        return parts
    }

    function parseWifi(raw) {
        const seen = new Map()
        for (const line of raw.trim().split("\n")) {
            if (!line) continue
            const p = splitNm(line)
            const ssid = p[1]
            if (!ssid) continue
            const sig = parseInt(p[2]) || 0
            if (!seen.has(ssid) || seen.get(ssid).signal < sig) {
                seen.set(ssid, {
                    ssid: ssid,
                    signal: sig,
                    inUse: p[0] === "*",
                    security: p[3] || ""
                })
            }
        }
        networks = Array.from(seen.values()).sort((a, b) => b.signal - a.signal)
    }

    function connectTo(ssid) {
        wifiConnectProc.command = ["nmcli", "device", "wifi", "connect", ssid]
        wifiConnectProc.running = true
    }

    Process {
        id: wifiListProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseWifi(text)
        }
    }

    Process {
        id: wifiConnectProc
        running: false
        onRunningChanged: {
            if (!running) {
                wifiListProc.running = true
                root.connectionChanged()
            }
        }
    }

    Timer {
        interval: 4000
        running: root.active
        repeat: true
        onTriggered: wifiListProc.running = true
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ── active connection ──
        Row {
            width: parent.width
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.connType === "wifi" ? String.fromCodePoint(0xF05A9)
                    : root.connType === "ethernet" ? String.fromCodePoint(0xF0200)
                    : String.fromCodePoint(0xF05AA)
                font.family: Theme.icon
                font.pixelSize: 18
                color: Theme.textPrimary
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.connType === "wifi" ? root.connName
                    : root.connType === "ethernet" ? "Ethernet"
                    : "Disconnected"
                color: Theme.textBright
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }

        // ── WIFI section header ──
        Item {
            width: parent.width
            height: 14

            Text {
                id: wifiHdr
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "WIFI"
                color: Theme.textDim
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 2
            }

            Rectangle {
                anchors.left: wifiHdr.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                height: 1
                color: Theme.divider
            }
        }

        // ── fixed-height scrollable wifi list ──
        Item {
            width: parent.width
            height: root.listHeight

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 2
                model: root.networks
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: netRow
                    required property var modelData
                    width: list.width
                    height: 34
                    radius: 11
                    color: modelData.inUse
                        ? Theme.rowSelected
                        : (netRowMa.containsMouse ? Theme.rowHover : "transparent")
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        id: sigDot
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: netRow.modelData.inUse ? Theme.accent : "transparent"
                        border.width: netRow.modelData.inUse ? 0 : 1
                        border.color: Theme.dotBorder
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        anchors.left: sigDot.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: sigBar.left
                        anchors.rightMargin: 10
                        text: netRow.modelData.ssid + (netRow.modelData.security ? "  " + String.fromCodePoint(0xF033E) : "")
                        color: netRow.modelData.inUse ? Theme.textBright : Theme.textTertiary
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: sigBar
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 4
                        radius: 2
                        color: Theme.trackBg2

                        Rectangle {
                            width: parent.width * (netRow.modelData.signal / 100)
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                        }
                    }

                    MouseArea {
                        id: netRowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.connectTo(netRow.modelData.ssid)
                    }
                }
            }

            // slim scroll indicator, only when the list overflows
            Rectangle {
                visible: list.contentHeight > list.height
                anchors.right: parent.right
                width: 3
                radius: 1.5
                color: Theme.subtleDivider
                y: list.visibleArea.yPosition * list.height
                height: Math.max(24, list.visibleArea.heightRatio * list.height)
            }

            // empty state, centered in the list area
            Text {
                visible: root.networks.length === 0
                anchors.centerIn: parent
                text: "Scanning…"
                color: Theme.textMuted
                font.pixelSize: 12
                font.italic: true
            }
        }

        Text {
            width: parent.width
            text: "Click to connect (saved or open networks).  Use nmtui for new secured ones."
            color: Theme.textMuted
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            topPadding: 4
        }
    }
}
