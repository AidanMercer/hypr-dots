pragma Singleton
import QtQuick
import Quickshell.Io

import "ThemeTokens.js" as Tokens

// Tokens for the active theme. We ask awww which wallpaper is showing, walk up
// to that folder and read its config.toml layered over the stock values in
// themes/default/config.toml. Re-queried on every wallpaper change (shell.qml
// wires ControlBus.wallpaperChanged -> reload). Key list lives in ThemeTokens.js.
QtObject {
    id: root

    property bool bubbles: Tokens.DEFAULTS.bubbles
    property bool cyber: Tokens.DEFAULTS.cyber
    property color accent: Tokens.DEFAULTS.accent
    property color accent2: Tokens.DEFAULTS.accent2
    property color accent3: Tokens.DEFAULTS.accent3
    property color accentWarn: Tokens.DEFAULTS.accent_warn
    property color accentDim: Tokens.DEFAULTS.accent_dim
    property color text: Tokens.DEFAULTS.text
    property color glass: Tokens.DEFAULTS.glass
    property string fontMono: Tokens.DEFAULTS.font_mono
    property int retriesLeft: 10

    function reload() { retriesLeft = 10; queryProc.running = true }

    // The "__OK__" marker tells us awww actually answered (vs. not-painted-yet at
    // login) — only then do we trust the parsed values and stop retrying.
    function parse(out) {
        if (out.indexOf("__OK__") === -1) return
        retriesLeft = 0
        const t = Tokens.parse(out)
        root.bubbles = t.bubbles
        root.cyber = t.cyber
        root.accent = t.accent
        root.accent2 = t.accent2
        root.accent3 = t.accent3
        root.accentWarn = t.accent_warn
        root.accentDim = t.accent_dim
        root.text = t.text
        root.glass = t.glass
        root.fontMono = t.font_mono
    }

    property Process _query: Process {
        id: queryProc
        command: ["bash", "-c",
            'img=$(awww query 2>/dev/null | sed -n "s/.*image: //p" | head -1); ' +
            '[ -n "$img" ] || exit 0; ' +
            'printf "__OK__\\n"; ' +
            'cat "$HOME/.config/themes/default/config.toml" "$(dirname "$img")/config.toml" 2>/dev/null; true']
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
