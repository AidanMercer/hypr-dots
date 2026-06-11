import QtQuick
import Quickshell.Bluetooth
import "../common"

// Bluetooth tab built on Quickshell's native BlueZ binding.
// When the BlueZ daemon isn't running, Bluetooth.defaultAdapter is null and we
// show an "unavailable" hint instead of an empty list. Discovery only runs
// while this tab is active so the radio isn't scanning in the background.
Item {
    id: root
    implicitHeight: col.implicitHeight

    property bool active: false
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool ready: adapter !== null

    // The device rows, shared by the Repeater (below) and keyboard navigation so
    // both index into the same ordering. Empty when the stack is off.
    readonly property var deviceList: ready && adapter.enabled
        ? sortDevices(Bluetooth.devices?.values ?? [])
        : []

    // Keyboard navigation, driven by ControlPopup's Up/Down/Enter. navIndex
    // highlights a device row (-1 = none); activateNav (dis)connects/pairs it.
    property int navIndex: -1
    readonly property int navCount: deviceList.length
    function activateNav() { tapDevice(deviceList[navIndex]) }
    onNavIndexChanged: if (navIndex >= 0) devList.positionViewAtIndex(navIndex, ListView.Contain)

    // height of the scrollable device area (≈ 5 rows); keep this constant so the
    // popup never grows when a scan turns up a pile of nearby devices.
    readonly property int listHeight: 200

    // connected first, then paired, then the rest — alphabetical within groups
    function sortDevices(list) {
        function rank(d) { return d.connected ? 0 : (d.paired ? 1 : 2) }
        return [...list].sort((a, b) => {
            const r = rank(a) - rank(b)
            if (r !== 0) return r
            return (a.deviceName || a.name || "").localeCompare(b.deviceName || b.name || "")
        })
    }

    function statusText(d) {
        if (d.pairing) return "Pairing…"
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…"
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
        if (d.connected) return d.batteryAvailable ? "Connected · " + Math.round(d.battery * 100) + "%" : "Connected"
        if (d.paired) return "Paired"
        return "Available"
    }

    function tapDevice(d) {
        if (d.connected) d.disconnect()
        else if (d.paired) d.connect()
        else d.pair()
    }

    // Scan only while the tab is open and the adapter is on.
    Binding {
        target: root.adapter
        property: "discovering"
        value: root.active && root.ready && root.adapter.enabled
        when: root.ready
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ── header: bluetooth label + power toggle ──
        Item {
            width: parent.width
            height: 24

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(root.ready && root.adapter.enabled ? 0xF00AF : 0xF00B2) // bluetooth / off
                    font.family: Theme.icon
                    font.pixelSize: 18
                    color: root.ready && root.adapter.enabled ? Theme.accent : Theme.textDim
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Bluetooth"
                    color: Theme.textBright
                    font.pixelSize: 13
                }
            }

            // toggle switch (only meaningful when the stack is up)
            Rectangle {
                id: toggle
                visible: root.ready
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 20
                radius: 10
                color: root.ready && root.adapter.enabled ? Theme.accent : Theme.trackBg2
                Behavior on color { ColorAnimation { duration: 150 } }

                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.textBright
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.ready && root.adapter.enabled ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.ready) root.adapter.enabled = !root.adapter.enabled
                }
            }
        }

        // ── unavailable hint ──
        Text {
            visible: !root.ready
            width: parent.width
            text: "Bluetooth unavailable.\nInstall bluez and start bluetooth.service."
            color: Theme.textMuted
            font.pixelSize: 12
            font.italic: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            topPadding: 6
        }

        // ── DEVICES section ──
        Item {
            visible: root.ready
            width: parent.width
            height: 14

            Text {
                id: devHdr
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "DEVICES"
                color: Theme.textDim
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 2
            }

            Rectangle {
                anchors.left: devHdr.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                height: 1
                color: Theme.divider
            }
        }

        // ── fixed-height scrollable device list ──
        Item {
            visible: root.ready
            width: parent.width
            height: root.listHeight

            ListView {
                id: devList
                anchors.fill: parent
                clip: true
                spacing: 2
                model: root.deviceList
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: btRow
                    required property var modelData
                    required property int index
                    readonly property bool navSelected: root.navIndex === index
                    width: devList.width
                    height: 38
                    radius: 11
                    color: modelData.connected
                        ? Theme.rowSelected
                        : ((navSelected || btRowMa.containsMouse) ? Theme.rowHover : "transparent")
                    // accent ring marks the keyboard-highlighted row.
                    border.width: navSelected ? 1 : 0
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        id: btIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(btRow.modelData.connected ? 0xF00B1 : 0xF00AF)
                        font.family: Theme.icon
                        font.pixelSize: 15
                        color: btRow.modelData.connected ? Theme.accent : Theme.textTertiary
                    }

                    Column {
                        anchors.left: btIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: btRow.modelData.deviceName || btRow.modelData.name || btRow.modelData.address
                            color: btRow.modelData.connected ? Theme.textBright : Theme.textTertiary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.statusText(btRow.modelData)
                            color: Theme.textMuted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: btRowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tapDevice(btRow.modelData)
                    }
                }
            }

            // slim scroll indicator, only when the list overflows
            Rectangle {
                visible: devList.contentHeight > devList.height
                anchors.right: parent.right
                width: 3
                radius: 1.5
                color: Theme.subtleDivider
                y: devList.visibleArea.yPosition * devList.height
                height: Math.max(24, devList.visibleArea.heightRatio * devList.height)
            }

            // empty state, centered in the list area
            Text {
                visible: root.deviceList.length === 0
                anchors.centerIn: parent
                width: parent.width
                text: !root.adapter.enabled ? "Turn Bluetooth on to scan for devices." : "Searching…"
                color: Theme.textMuted
                font.pixelSize: 12
                font.italic: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
