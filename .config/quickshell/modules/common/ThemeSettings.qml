pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Per-theme widget toggles (Super+Shift+/ → Settings). One JSON file in the
// state dir maps theme folder name → { slot: false } for every widget the user
// turned off; absence means on, so a fresh theme shows everything. The desktop
// loaders (clock/sysinfo/cava/lyrics) call on() in a binding — it reads `rev`,
// so every set() re-evaluates them and the widget mounts/unmounts live.
QtObject {
    id: ts

    property var map: ({})
    property int rev: 0

    function nameOf(dir) {
        return dir ? dir.replace(/\/+$/, "").split("/").pop() : ""
    }

    function on(dir, slot) {
        void ts.rev   // binding dependency — re-evaluate after every set()
        const t = ts.map[nameOf(dir)]
        return !(t && t[slot] === false)
    }

    function set(dir, slot, v) {
        const name = nameOf(dir)
        if (!name) return
        const m = ts.map
        if (v) {
            if (m[name]) delete m[name][slot]
            if (m[name] && Object.keys(m[name]).length === 0) delete m[name]
        } else {
            if (!m[name]) m[name] = {}
            m[name][slot] = false
        }
        ts.map = m
        ts.rev++
        stateFile.setText(JSON.stringify(m) + "\n")
    }

    function toggle(dir, slot) { ts.set(dir, slot, !ts.on(dir, slot)) }

    property FileView _file: FileView {
        id: stateFile
        path: Quickshell.stateDir + "/theme-settings.json"
        blockLoading: true
        preload: true
        printErrors: false
    }

    Component.onCompleted: {
        try {
            const m = JSON.parse(stateFile.text())
            if (m && typeof m === "object") { ts.map = m; ts.rev++ }
        } catch (e) {}
    }
}
