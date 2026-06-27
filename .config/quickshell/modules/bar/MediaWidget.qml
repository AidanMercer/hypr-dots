import QtQuick
import Quickshell.Services.Mpris
import "../common"

// Left of the bar: a minimal now-playing readout built on Quickshell's MPRIS
// binding. Shows a play/pause glyph + the current track; click toggles play/pause,
// scroll skips tracks. Hidden whenever nothing is playable so the bar stays clean.
//
// We pick the playing player if there is one, else the first available. That
// binding only re-runs when the player list changes (add/remove), not when an
// existing player flips play state — fine here, since a single player's own
// isPlaying/title update live once it's referenced.
Item {
    id: root
    height: Theme.bubbleHeight

    readonly property var player: {
        const ps = Mpris.players.values
        if (ps.length === 0) return null
        return ps.find(p => p.playbackState === MprisPlaybackState.Playing) ?? ps[0]
    }
    readonly property bool active: player !== null
    readonly property bool playing: active && player.playbackState === MprisPlaybackState.Playing

    // collapse to nothing when idle so the bubble behind it can hide too
    visible: active
    width: active ? row.width + 14 : 0

    readonly property string glyphPlay:  String.fromCodePoint(0xF040A)
    readonly property string glyphPause: String.fromCodePoint(0xF03E4)
    readonly property string glyphNote:  String.fromCodePoint(0xF075A) // mdi music

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.playing ? root.glyphPause : root.glyphPlay
            color: Theme.accent
            font.family: Theme.icon
            font.pixelSize: 13
            opacity: ma.containsMouse ? 1.0 : 0.85
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 220)
            elide: Text.ElideRight
            text: {
                if (!root.active) return ""
                const t = root.player.trackTitle || "Unknown"
                const a = root.player.trackArtist
                return a ? t + "  ·  " + a : t
            }
            color: root.playing ? Theme.textTertiary : Theme.textMuted
            font.family: root.cyberFont
            font.pixelSize: 12
            font.letterSpacing: Theme.cyber ? 0.5 : 0
        }
    }

    // mono face on cyber themes to match the HUD; default sans otherwise
    readonly property string cyberFont: Theme.cyber ? Theme.mono : "Noto Sans"

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: if (root.active && root.player.canTogglePlaying) root.player.togglePlaying()
        onWheel: (w) => {
            if (!root.active) return
            if (w.angleDelta.y > 0 && root.player.canGoNext) root.player.next()
            else if (w.angleDelta.y < 0 && root.player.canGoPrevious) root.player.previous()
        }
    }
}
