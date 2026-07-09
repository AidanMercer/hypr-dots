import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "../common"
import "units.js" as Units
import "emoji.js" as Emoji

// Fullscreen, transparent layer-shell overlay. The launcher card is centred
// inside it; clicking the surrounding scrim (or pressing Esc) dismisses it.
// Opened/closed over IPC: `qs ipc call launcher toggle` (wired to Super in
// hyprland.conf).
//
// Multi-mode: the default mode searches apps (+ inline calc / unit-convert /
// web-search). A leading prefix switches modes — `e ` emoji, `w ` windows,
// `c ` clipboard, `u ` units. `=` still forces the calculator.
PanelWindow {
    id: root

    property bool open: false
    // The monitor the launcher should appear on. Captured at open() time so a
    // wandering cursor (follow_mouse) can't remap the window mid-use.
    property var targetScreen: null
    screen: targetScreen

    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Grab the keyboard only while open, so typing goes to the search box and
    // other windows keep their focus the rest of the time.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    // Ignore the bar's exclusive zone so the scrim covers the full output,
    // including the strip under the bar (otherwise the top 44px stays bright).
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Stay mapped during the close animation, mirroring the popups.
    visible: open || exitTrans.running

    // ---- data ----------------------------------------------------------
    property string query: ""
    property int selectedIndex: 0
    // Reading DesktopEntries.applications in a live binding keeps the (lazy)
    // service populated; .values is the plain JS array of entries.
    readonly property var allApps: DesktopEntries.applications.values

    // The active mode + its argument (the query with the prefix stripped).
    // A prefix only triggers with a trailing space ("e ", not "e"), so plain
    // app names never get hijacked.
    readonly property var mode: {
        const q = query
        if (q.startsWith("e ")) return { kind: "emoji", arg: q.slice(2) }
        if (q.startsWith("w ")) return { kind: "window", arg: q.slice(2) }
        if (q.startsWith("c ")) return { kind: "clipboard", arg: q.slice(2) }
        if (q.startsWith("u ")) return { kind: "unit", arg: q.slice(2) }
        return { kind: "app", arg: q }
    }
    readonly property string modeLabel: ({
        emoji: "emoji", window: "windows", clipboard: "clipboard", unit: "units"
    })[mode.kind] || ""

    // Every result is normalised to a row with a `kind`; the delegate renders
    // and activate() dispatches off that. Keeps one list + one delegate for all
    // the modes instead of a widget per mode.
    readonly property var results: buildResults()
    function buildResults() {
        const m = root.mode
        if (m.kind === "emoji")
            return Emoji.search(m.arg, 60).map(x => ({ kind: "emoji", e: x.e, name: x.name }))
        if (m.kind === "window")
            return root.windowResults(m.arg)
        if (m.kind === "clipboard")
            return root.clipResults(m.arg)
        if (m.kind === "unit") {
            const u = Units.convert(m.arg, true)
            return u ? [{ kind: "unit", text: u.text, copy: u.copy }] : []
        }
        // app mode: apps, with calc / unit / web rows folded in
        const apps = filterApps(query, allApps).map(a => ({ kind: "app", entry: a, name: a.name }))
        if (query.length === 0) return apps
        const rows = []
        const calc = evalMath(query)
        if (calc) rows.push({ kind: "calc", expr: calc.expr, value: calc.value })
        const unit = Units.convert(query, false)
        if (unit) rows.push({ kind: "unit", text: unit.text, copy: unit.copy })
        return rows.concat(apps).concat([{ kind: "web" }])
    }

    // Evaluate a numeric expression safely: only digits/operators/parens pass the
    // gate (no letters → nothing to reference), so the eval can't reach any scope.
    // A plain number isn't treated as math unless the user leads with "=".
    function evalMath(raw) {
        let s = (raw || "").trim()
        const forced = s.startsWith("=")
        if (forced) s = s.slice(1).trim()
        if (s.length === 0) return null
        if (!/^[0-9+\-*/%.()\s]+$/.test(s)) return null
        if (!forced && !/[0-9]\s*[-+*/%]\s*[-+(]*\s*[0-9]/.test(s)) return null
        try {
            const v = Function('"use strict"; return (' + s + ')')()
            if (typeof v === "number" && isFinite(v))
                return { expr: s, value: Math.round(v * 1e10) / 1e10 }
        } catch (e) {}
        return null
    }

    function filterApps(q, apps) {
        const list = (apps || []).filter(a => a && a.name && !a.noDisplay)
        if (!q)
            return list.slice().sort((a, b) => a.name.localeCompare(b.name))
        const ql = q.toLowerCase()
        return list
            .filter(a => a.name.toLowerCase().includes(ql))
            .sort((a, b) => {
                // Prefix matches rank above mid-string matches.
                const ar = a.name.toLowerCase().startsWith(ql) ? 0 : 1
                const br = b.name.toLowerCase().startsWith(ql) ? 0 : 1
                if (ar !== br) return ar - br
                return a.name.localeCompare(b.name)
            })
    }

    // ---- window mode ---------------------------------------------------
    function windowResults(arg) {
        const q = (arg || "").trim().toLowerCase()
        let list = Hyprland.toplevels.values.map(t => {
            const o = t.lastIpcObject || {}
            return {
                kind: "window",
                address: o.address || "",
                title: o.title || "",
                cls: o.class || "",
                wsId: (o.workspace && o.workspace.id) || -1,
            }
        }).filter(w => w.address)   // freshly-opened windows arrive address-less
        if (q)
            list = list.filter(w => w.title.toLowerCase().includes(q)
                                  || w.cls.toLowerCase().includes(q))
        list.sort((a, b) => a.cls.localeCompare(b.cls) || a.title.localeCompare(b.title))
        return list
    }
    function iconForClass(cls) {
        if (!cls) return Quickshell.iconPath("application-x-executable")
        const entry = DesktopEntries.heuristicLookup(cls)
        const name = (entry && entry.icon) ? entry.icon : cls.toLowerCase()
        return Quickshell.iconPath(name, "application-x-executable")
    }
    function iconForApp(entry) {
        return Quickshell.iconPath((entry && entry.icon) || "", "application-x-executable")
    }
    function closeWindow(item) {
        if (!item || !item.address) return
        Hyprland.dispatch("closewindow address:" + item.address)
        Qt.callLater(Hyprland.refreshToplevels)
    }

    // ---- clipboard mode (reads cliphist; the shell's Super+V popup owns the
    // wl-paste watchers that fill it, so we only read here) -----------------
    property var clipEntries: []
    property bool clipLoaded: false
    function parseClip(text) {
        const out = []
        for (const line of text.split("\n")) {
            if (!line) continue
            const tab = line.indexOf("\t")
            if (tab < 1) continue
            const raw = line.slice(tab + 1)
            const m = raw.match(/^\[\[ binary data\s+(.+?)\s+(\w+)\s+(\d+)x(\d+)/)
            out.push({
                line: line,
                isImage: m !== null,
                preview: m ? ("image · " + m[2] + " · " + m[3] + "×" + m[4])
                           : raw.replace(/\s+/g, " ").trim()
            })
        }
        return out
    }
    Process {
        id: clipListProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.clipEntries = root.parseClip(text)
                root.clipLoaded = true
            }
        }
    }
    function loadClips() { clipListProc.running = true }
    function clipResults(arg) {
        const q = (arg || "").trim().toLowerCase()
        const all = q === "" ? clipEntries
                             : clipEntries.filter(e => e.preview.toLowerCase().includes(q))
        return all.slice(0, 40)
                  .map(e => ({ kind: "clip", line: e.line, preview: e.preview, isImage: e.isImage }))
    }
    function copyClip(item) {
        if (!item) return
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" | cliphist decode | wl-copy', "_", item.line])
        closeMenu()
    }
    function deleteClip(item) {
        if (!item) return
        clipDelProc.command = ["bash", "-c",
            'printf "%s" "$1" | cliphist delete', "_", item.line]
        clipDelProc.running = true
    }
    Process { id: clipDelProc; onExited: root.loadClips() }

    // Lazily pull clipboard history the first time the user enters clipboard
    // mode (mode is a fresh object each keystroke, so guard on clipLoaded).
    onModeChanged: if (mode.kind === "clipboard" && !clipLoaded) loadClips()

    // Keep the window list fresh while the launcher is up (filtering is local,
    // so we only need to re-query on real window lifecycle events).
    Connections {
        target: Hyprland
        enabled: root.open
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow":
            case "closewindow":
            case "movewindow":
            case "movewindowv2":
            case "activewindowv2":
                Hyprland.refreshToplevels()
            }
        }
    }

    // ---- actions -------------------------------------------------------
    function openMenu() {
        const m = Hyprland.focusedMonitor
        targetScreen = m ? (Quickshell.screens.find(s => s.name === m.name) ?? null) : null
        searchInput.text = ""   // resets query + selection via onTextChanged
        selectedIndex = 0
        clipLoaded = false
        Hyprland.refreshToplevels()
        open = true
        Qt.callLater(searchInput.forceActiveFocus)
    }
    function closeMenu() { open = false }
    function launch(entry) {
        if (!entry) return
        entry.execute()
        closeMenu()
    }
    function copyText(s) {
        Quickshell.execDetached(["wl-copy", "--", String(s)])
        closeMenu()
    }

    // Opens the query in the default browser (zen, via xdg-open). %1 is the
    // URL-encoded query — change searchUrl to use a different engine.
    property string searchUrl: "https://www.google.com/search?q=%1"
    function searchWeb(q) {
        if (!q) return
        Quickshell.execDetached(["xdg-open", root.searchUrl.arg(encodeURIComponent(q))])
        closeMenu()
    }

    function activate(item) {
        if (!item) return
        switch (item.kind) {
        case "app":    root.launch(item.entry); break
        case "web":    root.searchWeb(root.query); break
        case "calc":   root.copyText(item.value); break
        case "unit":   root.copyText(item.copy); break
        case "emoji":  root.copyText(item.e); break
        case "clip":   root.copyClip(item); break
        case "window":
            Hyprland.dispatch("focuswindow address:" + item.address)
            root.closeMenu()
            break
        }
    }
    // Delete key: destructive per-mode action on the selected row.
    function deleteSelected() {
        const it = root.results[root.selectedIndex]
        if (!it) return false
        if (it.kind === "window") { root.closeWindow(it); return true }
        if (it.kind === "clip") { root.deleteClip(it); return true }
        return false
    }

    function moveSel(delta) {
        if (results.length === 0) return
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta))
    }

    IpcHandler {
        target: "launcher"
        // Only `toggle` is wired to a key (Super tap / Super+R in hyprland.conf).
        function toggle(): void { root.open ? root.closeMenu() : root.openMenu() }
    }

    // ---- scrim (click-outside to dismiss) ------------------------------
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeMenu()
    }

    // ---- the floating launcher ----------------------------------------
    Item {
        id: morph
        width: searchBox.width
        height: layoutCol.height
        x: (parent.width - width) / 2
        // Centre the *search box* on screen (its half-height, not the whole
        // column's) so it stays put as the results list grows and shrinks.
        y: (parent.height - searchBox.height) / 2
        opacity: 0
        scale: 0.92
        transformOrigin: Item.Top

        states: State {
            name: "shown"
            when: root.open
            PropertyChanges { target: morph; opacity: 1; scale: 1 }
        }

        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                    SpringAnimation { property: "scale"; spring: 3; damping: 0.34; epsilon: 0.001 }
                }
            },
            Transition {
                id: exitTrans
                from: "shown"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 160; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; duration: 160; easing.type: Easing.InCubic }
                }
            }
        ]

        Column {
            id: layoutCol
            width: parent.width
            spacing: 10

            // ── the only frosted surface: the search box ──
            Rectangle {
                id: searchBox
                width: 520
                height: 52
                radius: Theme.popupRadius
                color: Theme.glassBg
                border.color: Theme.glassBorder
                border.width: 1

                // Swallow clicks on the box so they don't fall through to the
                // scrim and close the launcher.
                MouseArea { anchors.fill: parent }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: parent.radius
                    anchors.rightMargin: parent.radius
                    anchors.topMargin: 1
                    height: 1
                    color: Theme.glassHighlight
                }

                Text {
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF0349) // nf-md-magnify
                    font.family: Theme.icon
                    font.pixelSize: 18
                    color: Theme.textSecondary
                }

                // Little accent pill naming the active mode (hidden in app mode).
                Rectangle {
                    id: modePill
                    visible: root.modeLabel.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 22
                    width: pillText.implicitWidth + 18
                    radius: 11
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: root.modeLabel
                        color: Theme.accent
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 12
                    anchors.right: modePill.visible ? modePill.left : parent.right
                    anchors.rightMargin: modePill.visible ? 8 : 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.textBright
                    font.pixelSize: 16
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    clip: true
                    focus: true

                    onTextChanged: {
                        root.query = text
                        root.selectedIndex = 0
                    }

                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Down) { root.moveSel(1); e.accepted = true }
                        else if (e.key === Qt.Key_Up) { root.moveSel(-1); e.accepted = true }
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            root.activate(root.results[root.selectedIndex])
                            e.accepted = true
                        } else if (e.key === Qt.Key_Delete) {
                            if (root.deleteSelected()) e.accepted = true
                        } else if (e.key === Qt.Key_Escape) {
                            root.closeMenu(); e.accepted = true
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search apps…"
                        color: Theme.textMuted
                        font: searchInput.font
                        visible: searchInput.text.length === 0
                    }
                }
            }

            // ── results: their own frosted panel, floating below the box ──
            Rectangle {
                id: resultsPanel
                width: searchBox.width
                height: resultsCol.implicitHeight + 16
                radius: Theme.popupRadius
                color: Theme.glassBg
                border.color: Theme.glassBorder
                border.width: 1

                MouseArea { anchors.fill: parent }   // swallow scrim clicks

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: parent.radius
                    anchors.rightMargin: parent.radius
                    anchors.topMargin: 1
                    height: 1
                    color: Theme.glassHighlight
                }

                Column {
                    id: resultsCol
                    x: 8
                    y: 8
                    width: parent.width - 16

                    ListView {
                        id: list
                        width: parent.width
                        height: Math.min(root.results.length, 8) * 42
                        visible: root.results.length > 0
                        clip: true
                        model: root.results
                        currentIndex: root.selectedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property string kind: modelData.kind
                            width: ListView.view.width
                            height: 42
                            radius: 11
                            color: ListView.isCurrentItem
                                ? Theme.rowSelected
                                : (rowMa.containsMouse ? Theme.rowHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            // ── left visual: icon / emoji / glyph / dot ──
                            IconImage {
                                visible: rowItem.kind === "app" || rowItem.kind === "window"
                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                source: rowItem.kind === "app"
                                    ? root.iconForApp(rowItem.modelData.entry)
                                    : root.iconForClass(rowItem.modelData.cls)
                            }
                            Text {
                                visible: rowItem.kind === "emoji"
                                anchors.left: parent.left
                                anchors.leftMargin: 11
                                anchors.verticalCenter: parent.verticalCenter
                                text: rowItem.kind === "emoji" ? rowItem.modelData.e : ""
                                font.pixelSize: 20
                            }
                            Text {
                                visible: rowItem.kind === "calc" || rowItem.kind === "unit" || rowItem.kind === "web"
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                // nf-md-equal for calc/unit, nf-md-magnify for web
                                text: String.fromCodePoint(rowItem.kind === "web" ? 0xF0349 : 0xF0DF1)
                                font.family: Theme.icon
                                font.pixelSize: 16
                                color: Theme.accent
                            }
                            Rectangle {
                                visible: rowItem.kind === "clip"
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8; height: 8; radius: 4
                                color: rowItem.ListView.isCurrentItem ? Theme.accent : "transparent"
                                border.width: rowItem.ListView.isCurrentItem ? 0 : 1
                                border.color: Theme.dotBorder
                            }

                            // ── primary label ──
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 40
                                anchors.right: rightLabel.visible ? rightLabel.left : parent.right
                                anchors.rightMargin: rowItem.kind === "window" ? 8 : 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    const d = rowItem.modelData
                                    switch (rowItem.kind) {
                                    case "web":    return "Search the web for “" + root.query + "”"
                                    case "calc":   return d.expr
                                    case "unit":   return d.text
                                    case "emoji":  return d.name
                                    case "clip":   return d.preview
                                    case "window": return d.title || d.cls || "window"
                                    default:       return d.name || ""
                                    }
                                }
                                textFormat: Text.PlainText
                                color: rowItem.ListView.isCurrentItem ? Theme.textBright : Theme.textTertiary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            // ── right-side secondary: calc result / window class ──
                            Text {
                                id: rightLabel
                                visible: rowItem.kind === "calc" || rowItem.kind === "window"
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, rowItem.width * 0.42)
                                horizontalAlignment: Text.AlignRight
                                text: {
                                    if (rowItem.kind === "calc") return "= " + rowItem.modelData.value
                                    if (rowItem.kind === "window") return rowItem.modelData.cls
                                    return ""
                                }
                                textFormat: Text.PlainText
                                color: rowItem.kind === "calc" ? Theme.accent : Theme.textMuted
                                font.pixelSize: rowItem.kind === "calc" ? 13 : 11
                                font.bold: rowItem.kind === "calc"
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = rowItem.index
                                onClicked: root.activate(root.results[rowItem.index])
                            }
                        }
                    }

                    // Empty state — mode-aware.
                    Text {
                        visible: root.results.length === 0
                        width: parent.width
                        text: ({
                            emoji: "No emoji found",
                            window: "No open windows",
                            clipboard: root.clipEntries.length === 0 ? "Nothing copied yet" : "No matches",
                            unit: "try  10 km to mi  ·  72f in c  ·  2gb mb",
                            app: "No applications"
                        })[root.mode.kind] || "No results"
                        color: Theme.textMuted
                        font.pixelSize: 13
                        font.italic: true
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 8
                        bottomPadding: 8
                    }

                    // Mode hints — only in the default app mode so the prefixes
                    // are discoverable without cluttering the other modes.
                    Item {
                        width: parent.width
                        height: 22
                        visible: root.mode.kind === "app"
                        Text {
                            anchors.centerIn: parent
                            text: "=  calc      e  emoji      w  windows      c  clipboard      u  units"
                            color: Theme.textMuted
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
