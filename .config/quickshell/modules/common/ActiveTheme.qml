pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Single source of truth for "which theme folder is each monitor showing?".
//
// Every per-theme loader used to fork its own `awww query` to answer this for one
// monitor; this asks once for ALL of them and hands out the answer. The loaders
// read dirFor(monitorName) instead of spawning bash+awww each. Re-queried on every
// wallpaper change (theme switch) and retried at login until awww has painted.
//
// Parsing mirrors the old per-loader grep+sed exactly: find the awww line that
// mentions this monitor's name, take everything after the last "image: ", and walk
// up to its folder. Robust to awww's odd leading ": " on each line.
//
// Themes can ship several wallpapers (wallpaper.jpg, wallpaper2.mp4, ...), so the
// map keeps the full IMAGE path awww reported — imgFor() tells you which variant a
// monitor is on (video variants show as their <name>.still.png), dirFor() still
// walks up to the theme folder for the widget loaders.
QtObject {
    id: at

    property var map: ({})        // monitorName -> active wallpaper image ("" absent)
    property bool ready: false    // awww has answered at least once
    property int retriesLeft: 10

    function imgFor(name) { return (name && at.map[name]) ? at.map[name] : "" }
    function dirFor(name) {
        const img = at.imgFor(name)
        return img ? img.replace(/\/[^/]*$/, "") : ""   // dirname(img)
    }

    readonly property string focusedDir: {
        const m = Hyprland.focusedMonitor
        return m ? at.dirFor(m.name) : ""
    }
    readonly property string focusedImg: {
        const m = Hyprland.focusedMonitor
        return m ? at.imgFor(m.name) : ""
    }

    function reload() { at.ready = false; at.retriesLeft = 10; queryProc.running = true }

    // "__OK__" proves awww actually answered (vs not-painted-yet at login). Until
    // then we keep the old map and keep retrying.
    function parse(text) {
        if (text.indexOf("__OK__") === -1) return
        if (text.indexOf("__NOAWWW__") !== -1) {
            // without the daemon every theme widget would just silently vanish —
            // say why once instead of retrying forever
            console.warn("[ActiveTheme] awww isn't installed — theme widgets can't resolve; pacman -S awww")
            at.retriesLeft = 0
            at.ready = true
            return
        }
        const lines = text.split("\n")
        const m = {}
        for (const screen of Quickshell.screens) {
            const name = screen.name
            const line = lines.find(l => l.indexOf(name + ":") !== -1)
            if (!line) continue
            const k = line.lastIndexOf("image: ")
            if (k === -1) continue
            const img = line.substring(k + 7).trim()
            if (img) m[name] = img
        }
        at.map = m
        at.ready = true
        // a monitor can paint late at login/hotplug — keep polling until every
        // screen resolved, only then stop retrying.
        if (Quickshell.screens.every(s => m[s.name])) at.retriesLeft = 0
        // a monitor plugged in after boot stays black: the daemon runs --no-cache
        // and the splash only restores at login. push the last wallpaper to just
        // the black outputs. needs one screen already resolved so this can never
        // fire at cold boot and race the splash restore.
        const dark = Quickshell.screens.filter(s => !m[s.name]).map(s => s.name)
        if (dark.length && dark.length < Quickshell.screens.length && !restoreProc.running) {
            restoreProc.command = ["sh", "-c",
                'p=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/world80/last-wallpaper" 2>/dev/null); ' +
                '[ -n "$p" ] && [ -f "$p" ] && awww img -o "$1" "$p"', "sh", dark.join(",")]
            restoreProc.running = true
        }
    }

    property Process _restore: Process { id: restoreProc }

    property Process _query: Process {
        id: queryProc
        command: ["bash", "-c",
            'printf "__OK__\\n"; if command -v awww >/dev/null; then awww query 2>/dev/null; else printf "__NOAWWW__\\n"; fi']
        stdout: StdioCollector { onStreamFinished: at.parse(text) }
    }

    // awww may not have painted yet at login — keep asking until it answers.
    property Timer _retry: Timer {
        interval: 1500
        repeat: true
        running: at.retriesLeft > 0
        onTriggered: { at.retriesLeft--; queryProc.running = true }
    }

    // re-ask on every theme switch
    property Connections _bus: Connections {
        target: ControlBus
        function onWallpaperChanged() { at.reload() }
    }

    // and on monitor hotplug
    property Connections _screens: Connections {
        target: Quickshell
        function onScreensChanged() { at.reload() }
    }

    Component.onCompleted: queryProc.running = true
}
