pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Global interface-scale factor. One knob (Settings → Interface scale) that the
// control center and every theme's desktop widgets multiply into their own
// size: the control popup scales its card transform by this, and ThemePalette
// folds it into pal.uiScale so sysinfo/clock/lyrics/cava grow in place. Snapped
// to `step`, clamped to [min,max], persisted to the state dir so it survives a
// shell restart. Setting it re-evaluates the bindings live — drag = live resize.
QtObject {
    id: root

    readonly property real min: 0.8
    readonly property real max: 1.4
    readonly property real step: 0.05

    property real factor: 1.0

    function clamp(v) { return Math.max(min, Math.min(max, v)) }

    function setFactor(v) {
        if (isNaN(v)) return
        const snapped = clamp(Math.round(clamp(v) / step) * step)
        root.factor = snapped
        file.setText(snapped.toFixed(3) + "\n")
    }

    function nudge(d) { root.setFactor(root.factor + d) }

    property FileView _file: FileView {
        id: file
        path: Quickshell.stateDir + "/ui-scale"
        blockLoading: true
        preload: true
        printErrors: false
        onLoaded: {
            const v = parseFloat(file.text().trim())
            if (!isNaN(v)) root.factor = root.clamp(v)
        }
    }
}
