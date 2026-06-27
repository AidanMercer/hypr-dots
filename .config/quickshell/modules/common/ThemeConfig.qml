pragma Singleton
import QtQuick
import Quickshell.Io

// Per-theme bar settings. Each theme folder (~/.config/themes/<name>/) may drop a
// config.toml next to its wallpaper; we ask awww which wallpaper is showing, walk
// up to that folder and read it. Re-queried on every wallpaper change (shell.qml
// wires ControlBus.wallpaperChanged -> reload).
//
// Recognised keys (flat TOML):
//   bubbles = true | false   # glass pills behind the bar clusters (default: false)
//   accent  = "#rrggbb"      # glow color of the center cava visualizer
//   cyber   = true | false   # cyberpunk chrome on the control popup (default: false)
//
// When cyber is on, the secondary palette below tints the control popup's HUD
// (cyan rules, magenta alerts, amber mid-load, dim traces) to match the moon
// theme's desktop widgets, which read the same keys via MoonPalette.qml.
//   accent2     = "#rrggbb"  # secondary cyan
//   accent3     = "#rrggbb"  # alert magenta
//   accent_warn = "#rrggbb"  # amber / mid threshold
//   accent_dim  = "#rrggbb"  # muted trace (dividers, ghosts, footer)
QtObject {
    id: root

    property bool bubbles: false
    property bool cyber: false
    // default matches Theme.accent; hardcoded here to avoid a singleton import cycle.
    property color accent: "#a8b5e8"
    // secondary palette — defaults are the moon theme's neon set so a cyber theme
    // that only sets `cyber = true` still gets a coherent look.
    property color accent2: "#00e5ff"
    property color accent3: "#ff2e6c"
    property color accentWarn: "#ffae3d"
    property color accentDim: "#7c7a3a"
    property int retriesLeft: 10

    function reload() { retriesLeft = 10; queryProc.running = true }

    // The "__OK__" marker tells us awww actually answered (vs. not-painted-yet at
    // login) — only then do we trust the parsed value and stop retrying. A theme
    // with no config.toml just yields the marker alone -> defaults hold.
    function parse(text) {
        if (text.indexOf("__OK__") === -1) return
        retriesLeft = 0
        let b = false
        let cy = false
        let a = "#a8b5e8"
        // secondary palette — seed with the neon defaults so a cyber theme that
        // omits these keys still resolves to a coherent look (matches the property
        // defaults above and MoonPalette.qml's fallbacks).
        let a2 = "#00e5ff", a3 = "#ff2e6c", aw = "#ffae3d", ad = "#7c7a3a"
        function pick(line, key) {
            // hex only, mirroring MoonPalette._pick so the two parsers stay in lockstep
            const re = new RegExp("^\\s*" + key + "\\s*=\\s*[\"']?(#[0-9a-fA-F]{3,8})[\"']?", "i")
            const mm = line.match(re)
            return mm ? mm[1] : null
        }
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*bubbles\s*=\s*(true|false)\b/i)
            if (m) b = m[1].toLowerCase() === "true"
            const cm = line.match(/^\s*cyber\s*=\s*(true|false)\b/i)
            if (cm) cy = cm[1].toLowerCase() === "true"
            const c = line.match(/^\s*accent\s*=\s*["']?(#[0-9a-fA-F]{3,8}|[a-zA-Z]+)["']?/)
            if (c) a = c[1]
            // accent's regex stops at "=", so it never matches accent2/accent3/etc.
            const p2 = pick(line, "accent2");     if (p2) a2 = p2
            const p3 = pick(line, "accent3");     if (p3) a3 = p3
            const pw = pick(line, "accent_warn"); if (pw) aw = pw
            const pd = pick(line, "accent_dim");  if (pd) ad = pd
        }
        root.bubbles = b
        root.cyber = cy
        root.accent = a
        root.accent2 = a2
        root.accent3 = a3
        root.accentWarn = aw
        root.accentDim = ad
    }

    property Process _query: Process {
        id: queryProc
        command: ["bash", "-c",
            'img=$(awww query 2>/dev/null | sed -n "s/.*image: //p" | head -1); ' +
            '[ -n "$img" ] || exit 0; ' +
            'printf "__OK__\\n"; ' +
            'cat "$(dirname "$img")/config.toml" 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    // awww may not have painted yet at login — keep asking until it answers.
    property Timer _retry: Timer {
        interval: 1500
        repeat: true
        running: root.retriesLeft > 0
        onTriggered: { root.retriesLeft--; queryProc.running = true }
    }

    Component.onCompleted: queryProc.running = true
}
