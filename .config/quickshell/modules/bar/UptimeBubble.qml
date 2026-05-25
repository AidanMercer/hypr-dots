import QtQuick
import Quickshell.Io
import "../common"

// Shows how long the system has been up. We read /proc/uptime (its first
// number is the boot age in seconds, as a float) once on startup, then tick a
// local timer every second so the display stays live without re-reading the
// file constantly. We re-sync from /proc/uptime every few minutes to correct
// any drift (e.g. after the machine suspends).
Bubble {
    id: root
    width: uptimeRow.width + 24

    // Seconds since boot. Updated from /proc/uptime, advanced by the tick timer.
    property real seconds: 0

    readonly property string iconArch: String.fromCodePoint(0xF303) // nf-linux-archlinux

    function formatUptime(s) {
        const total = Math.floor(s)
        const d = Math.floor(total / 86400)
        const h = Math.floor((total % 86400) / 3600)
        const m = Math.floor((total % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    Row {
        id: uptimeRow
        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconArch
            color: Theme.accent
            font.family: Theme.icon
            font.pixelSize: 14
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "up " + root.formatUptime(root.seconds)
            color: Theme.textSecondary
            font.pixelSize: 13
            font.family: Theme.mono
        }
    }

    // Reads /proc/uptime and parses the first token into root.seconds.
    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const first = parseFloat(text.trim().split(/\s+/)[0])
                if (!isNaN(first)) root.seconds = first
            }
        }
    }

    // Advance locally every second so the minute display rolls over on time.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.seconds += 1
    }

    // Re-sync from the kernel periodically to correct drift.
    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: uptimeProc.running = true
    }
}
