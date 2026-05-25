import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../common"

Bubble {
    id: root
    width: wsRow.width + 12

    // The Hyprland monitor this bar lives on; each bar passes its own.
    required property var monitor

    // A strip of `wsCount` workspaces that PAGES in blocks of 10: page 1 is
    // 1..10, page 2 is 11..20, etc. Each slot shows the icon of an app living
    // on that workspace, or a small dot when empty.
    readonly property int wsCount: 10
    // This monitor's active workspace — not the global focus — so each
    // monitor's bar reflects the workspace it is actually showing.
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1
    // The first workspace id of the page the active workspace lives on.
    // floor((id-1)/10)*10 + 1 maps 1..10 -> 1, 11..20 -> 11, and so on, so the
    // strip slides to the right block of ten when you scroll past 10. Special
    // / scratch workspaces have negative ids; fall back to page 1 for those.
    readonly property int pageBase: activeWsId >= 1
        ? Math.floor((activeWsId - 1) / wsCount) * wsCount + 1
        : 1

    readonly property int slotSize: 22
    readonly property int slotSpacing: 4

    // Keep the desktop-entry database alive. DesktopEntries.applications is a
    // LAZY model: it only scans .desktop files while something is observing
    // it, so heuristicLookup() returns null unless we hold a live binding to
    // it. Declaring this property keeps that subscription open for the bar's
    // lifetime. (Discovered the hard way — lookups silently fail without it.)
    readonly property int _desktopEntriesKeepAlive: DesktopEntries.applications.values.length

    // Hyprland.workspaces and .monitors auto-populate, but Hyprland.toplevels
    // does NOT: it stays empty until refreshToplevels() is called. At login the
    // bar starts with windows already open and no event incoming, so without
    // this kick every slot reads as unoccupied and shows a dot — no app icons.
    // Events DO add/remove toplevels in the model on their own, but a window
    // opened via `openwindow` arrives with an incomplete lastIpcObject (no
    // class yet) and is never refilled on its own — so we re-query on each
    // window lifecycle event to keep every window's class populated.
    Component.onCompleted: Hyprland.refreshToplevels()
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow":     // new window — fill in its class
            case "closewindow":    // window gone
            case "movewindow":     // window changed workspace
            case "movewindowv2":
            case "activewindowv2": // focus changed — refresh focusHistoryID
                Hyprland.refreshToplevels()
            }
        }
    }

    // Resolve a window class to an icon URL, degrading gracefully:
    //   desktop-entry icon  ->  the class name as an icon  ->  generic app
    function iconForClass(cls) {
        if (!cls)
            return ""
        const entry = DesktopEntries.heuristicLookup(cls)
        const name = (entry && entry.icon) ? entry.icon : cls.toLowerCase()
        return Quickshell.iconPath(name, "application-x-executable")
    }

    // Choose the single icon to show for a workspace's windows: the one that
    // is — or was most recently — focused there. Hyprland ranks every window
    // by focusHistoryID (0 = currently focused, then 1, 2, …), so the smallest
    // value on a workspace is its active-or-last-active window. A just-opened
    // window can briefly lack a class (see refreshToplevels note above), so we
    // only consider windows that have one, and fall back to the generic app
    // icon if none does yet — an occupied slot is never blank.
    function iconForWindows(wins) {
        let best = null
        let bestFh = Infinity
        for (const w of wins) {
            const cls = w.lastIpcObject?.class ?? ""
            if (!cls)
                continue
            const fh = w.lastIpcObject?.focusHistoryID ?? Infinity
            if (fh < bestFh) {
                best = w
                bestFh = fh
            }
        }
        return best ? iconForClass(best.lastIpcObject.class)
                    : Quickshell.iconPath("application-x-executable")
    }

    // Sliding highlight behind the active workspace. Hidden for special /
    // scratch workspaces (negative ids), which sit on no page.
    Rectangle {
        id: activeIndicator
        visible: root.activeWsId >= 1
        width: root.slotSize
        height: root.slotSize
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        // Offset within the current page, not from workspace 1.
        x: wsRow.x + (root.activeWsId - root.pageBase) * (root.slotSize + root.slotSpacing)
        color: Theme.glassBg
        border.color: Theme.glassBorder
        border.width: 1

        Behavior on x {
            SpringAnimation { spring: 2.6; damping: 0.28; epsilon: 0.1 }
        }
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: root.slotSpacing

        Repeater {
            model: root.wsCount

            delegate: Item {
                id: slot
                required property int index
                readonly property int wsId: root.pageBase + index
                readonly property bool isActive: root.activeWsId === wsId

                // Windows Hyprland reports on this workspace. Reading the
                // toplevel list plus each window's .workspace registers them
                // as dependencies, so this re-evaluates when a window opens,
                // closes, or moves between workspaces.
                readonly property var windowsHere: Hyprland.toplevels.values
                    .filter(t => (t.workspace?.id ?? -1) === wsId)
                readonly property bool isOccupied: windowsHere.length > 0
                // A single representative icon for the windows here.
                readonly property string iconSource: isOccupied
                    ? root.iconForWindows(windowsHere)
                    : ""

                // 0 = normal (icon/dot), 1 = number revealed (Super held). A
                // single animated value drives the whole transition: the number
                // fades in while the app icon shrinks into the corner.
                property real reveal: BarState.showNumbers ? 1 : 0
                Behavior on reveal {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                width: root.slotSize
                height: root.slotSize

                // Empty workspace: a small dot. Fades out as the number fades
                // in, so an empty slot reads purely as its number while held.
                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: slot.isActive ? Theme.textBright : Theme.textMuted
                    opacity: slot.isOccupied ? 0 : (1 - slot.reveal)
                    visible: opacity > 0.01
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // Occupied workspace: the app icon. Full size and centred
                // normally; while the number is revealed it shrinks and slides
                // into the bottom-right corner as a small badge. Both size and
                // position are driven off `reveal`, so they animate together.
                IconImage {
                    visible: slot.isOccupied
                    source: slot.iconSource
                    width: 16 - 7 * slot.reveal      // 16 -> 9
                    height: width
                    // (slotSize - size)/2 centres it; *1 pins it to the corner.
                    x: (slot.width - width) * (0.5 + 0.5 * slot.reveal)
                    y: (slot.height - height) * (0.5 + 0.5 * slot.reveal)
                    opacity: slot.isActive ? 1.0 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                // The workspace number — the main glyph while Super is held.
                Text {
                    anchors.centerIn: parent
                    text: slot.wsId
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.bold: slot.isActive
                    color: slot.isActive ? Theme.textBright : Theme.textSecondary
                    opacity: slot.reveal
                    visible: opacity > 0.01
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch(`workspace ${slot.wsId}`)
                }
            }
        }
    }
}
