import QtQuick
import Quickshell.Io
import "../common"

// Top-right bar bubble: live CPU / RAM / GPU usage as little icon + percent
// groups, in the same frosted glass as the other bubbles.
//
//   • CPU  — % busy over the last poll, from the delta of two /proc/stat samples
//   • RAM  — used / total, from /proc/meminfo (MemTotal vs MemAvailable)
//   • GPU  — nvidia-smi utilisation on the desktop; falls back to AMD's sysfs
//            busy file, else shows "—" (e.g. the Intel laptop, where no simple
//            per-cent metric is exposed). Stays portable across both machines.
Bubble {
    id: root
    width: statRow.width + 24

    // Each metric: 0–100, or -1 when not yet sampled / unavailable (renders "—").
    property int cpuPercent: -1
    property int ramPercent: -1
    property int gpuPercent: -1

    // CPU% needs two samples, so we keep the previous /proc/stat totals and diff.
    property real prevTotal: 0
    property real prevIdle: 0

    readonly property int pollInterval: 2000

    function pct(v) { return v < 0 ? "—" : v + "%" }

    // ── one tick drives all three reads ──
    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuProc.running = true
            ramProc.running = true
            gpuProc.running = true
        }
    }

    // ── CPU: busy fraction between consecutive /proc/stat samples ──
    Process {
        id: cpuProc
        command: ["cat", "/proc/stat"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseCpu(text) }
    }
    function parseCpu(raw) {
        // first line: "cpu  user nice system idle iowait irq softirq steal …"
        const f = raw.split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
        if (f.length < 5) return
        const idle = f[3] + f[4]                       // idle + iowait
        const total = f.reduce((a, b) => a + b, 0)
        const dTotal = total - root.prevTotal
        const dIdle = idle - root.prevIdle
        // Skip the very first sample (prevTotal still 0) so we report an
        // instantaneous figure, not the average since boot.
        if (root.prevTotal > 0 && dTotal > 0)
            root.cpuPercent = Math.round(100 * (dTotal - dIdle) / dTotal)
        root.prevTotal = total
        root.prevIdle = idle
    }

    // ── RAM: used = total - available ──
    Process {
        id: ramProc
        command: ["cat", "/proc/meminfo"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseRam(text) }
    }
    function parseRam(raw) {
        let total = 0, avail = 0
        for (const line of raw.split("\n")) {
            if (line.startsWith("MemTotal:")) total = parseInt(line.replace(/\D+/g, ""))
            else if (line.startsWith("MemAvailable:")) avail = parseInt(line.replace(/\D+/g, ""))
        }
        if (total > 0) root.ramPercent = Math.round(100 * (total - avail) / total)
    }

    // ── GPU: nvidia-smi → AMD sysfs → nothing (shows "—") ──
    Process {
        id: gpuProc
        // tr -dc keeps only digits: nvidia-smi prints its "driver not loaded"
        // error to *stdout* (not stderr), so we must filter to a number rather
        // than trust non-empty output — otherwise the error text would count as
        // a reading and the AMD fallback would never run.
        command: ["sh", "-c",
            "v=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -dc '0-9'); " +
            "if [ -n \"$v\" ]; then echo \"$v\"; " +
            "else for f in /sys/class/drm/card*/device/gpu_busy_percent; do [ -r \"$f\" ] && cat \"$f\" && break; done; fi"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseGpu(text) }
    }
    function parseGpu(raw) {
        const n = parseInt(raw.trim())
        root.gpuPercent = isNaN(n) ? -1 : n
    }

    // ── one icon + percentage pair; fixed-width number so the bar never jiggles
    //    as values change (1% → 100%) ──
    component Stat: Row {
        id: stat
        property string glyph: ""
        property int value: -1
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: stat.glyph
            font.family: Theme.icon
            font.pixelSize: 14
            color: Theme.textSecondary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            horizontalAlignment: Text.AlignRight
            text: root.pct(stat.value)
            color: Theme.textPrimary
            font.pixelSize: 13
            font.family: Theme.mono
            font.weight: Font.Medium
        }
    }

    Row {
        id: statRow
        anchors.centerIn: parent
        spacing: 12

        Stat { glyph: String.fromCodePoint(0xF0EE0); value: root.cpuPercent } // nf-md-cpu_64_bit
        Stat { glyph: String.fromCodePoint(0xF035B); value: root.ramPercent } // nf-md-memory
        Stat { glyph: String.fromCodePoint(0xF0FD8); value: root.gpuPercent } // nf-md-expansion_card_variant
    }
}
