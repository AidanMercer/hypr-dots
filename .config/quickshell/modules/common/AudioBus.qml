pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// One shared audio-energy feed for the whole shell.
//
// Runs a SINGLE cava capture (only while something is actually playing) and
// broadcasts smoothed energy bands, so any widget can react to the music without
// each spawning its own cava reader. The envelope math (fast attack / slow release,
// the silence gate) is lifted from the moon lyric visualizer, which proved it.
//
// Two ways to consume it:
//   - in-repo widgets: import the singleton and bind to level/bass/mid/high/silent.
//   - theme widgets (loaded by file:// url, so they can't import a singleton): read
//     the mirror file at $XDG_RUNTIME_DIR/quickshell-audio-pulse. One line:
//       "level;bass;mid;high;silent"   floats 0..1, silent is 0/1
//     Watch it with FileView { watchChanges: true }, or poll it on a Timer.
//
// Fully fail-open: nothing playing -> no cava -> bands sit at 0 and ready=false.
QtObject {
    id: bus

    // smoothed bands, 0..1
    property real level: 0      // overall energy — good for ripples / scale swells
    property real bass:  0      // low end (the thump) — good for glow / pulse
    property real mid:   0
    property real high:  0
    property bool silent: false
    property bool ready: false  // false when there's no live feed

    // run cava only while a player is actually playing — no music, no capture stream
    readonly property bool playing:
        Mpris.players.values.some(p => p.playbackState === MprisPlaybackState.Playing)

    // envelope state (attack fast, release slow) + hysteresis silence gate
    property real _envL: 0
    property real _envB: 0
    property real _envM: 0
    property real _envH: 0
    property real _lastWall: 0
    property real _quietSince: 0
    readonly property real silenceEnter: 0.040
    readonly property real silenceExit:  0.075
    readonly property int  silenceDebounceMs: 180

    function _smooth(prev, inst, atk, rel) {
        return inst > prev ? prev + (inst - prev) * atk : prev + (inst - prev) * rel
    }

    function parseFrame(line) {
        const parts = line.split(";")
        const n = parts.length
        if (n === 0) return
        let sum = 0, cnt = 0
        let bSum = 0, bN = 0, mSum = 0, mN = 0, hSum = 0, hN = 0
        for (let i = 0; i < n; i++) {
            if (parts[i] === "") continue
            let v = parseInt(parts[i]) / 1000
            if (v < 0.05) v = 0                    // same noise floor as the reactor
            if (i > 0) { sum += v; cnt++ }         // overall skips bin 0 (DC-ish)
            const frac = i / n
            if (i <= 2)            { bSum += v; bN++ }   // bass: lowest bins
            else if (frac < 0.55) { mSum += v; mN++ }   // mids
            else                  { hSum += v; hN++ }   // highs
        }
        if (cnt === 0) return
        _envL = _smooth(_envL, sum / cnt,              0.6, 0.25)
        _envB = _smooth(_envB, bN ? bSum / bN : 0,     0.7, 0.35)
        _envM = _smooth(_envM, mN ? mSum / mN : 0,     0.6, 0.30)
        _envH = _smooth(_envH, hN ? hSum / hN : 0,     0.6, 0.30)
        level = _envL; bass = _envB; mid = _envM; high = _envH
        ready = true
        _lastWall = Date.now()
        if (_envL < silenceEnter) {
            if (_quietSince === 0) _quietSince = _lastWall
            if (_lastWall - _quietSince >= silenceDebounceMs) silent = true
        } else if (_envL > silenceExit) {
            _quietSince = 0
            silent = false
        }
    }

    // push the current bands out to the mirror file (called ~20fps by _pump)
    readonly property string _outPath: {
        const rt = Quickshell.env("XDG_RUNTIME_DIR")
        const base = (rt && String(rt).length) ? String(rt) : Quickshell.stateDir
        return base + "/quickshell-audio-pulse"
    }
    function _writeOut() {
        outFile.setText(level.toFixed(3) + ";" + bass.toFixed(3) + ";" + mid.toFixed(3)
                        + ";" + high.toFixed(3) + ";" + (silent ? 1 : 0) + "\n")
    }

    // zero everything and push one final frame so watchers relax when music stops
    onPlayingChanged: if (!playing) {
        level = 0; bass = 0; mid = 0; high = 0; silent = false; ready = false
        _envL = 0; _envB = 0; _envM = 0; _envH = 0
        _writeOut()
    }

    // one cava for the whole shell; restarts itself if it dies mid-playback
    property Process _cava: Process {
        id: cavaProc
        running: bus.playing
        command: ["cava", "-p", Qt.resolvedUrl("cava-audiobus.conf").toString().replace("file://", "")]
        stdout: SplitParser { onRead: line => bus.parseFrame(line) }
        onRunningChanged: if (bus.playing && !running) cavaRestart.start()
    }
    property Timer _cavaRestart: Timer {
        id: cavaRestart
        interval: 2000
        onTriggered: if (bus.playing) cavaProc.running = true
    }

    // write-only mirror. non-atomic so the inode stays put and watchers' inotify
    // keeps firing (atomic writes rename over the file and drop the watch).
    property FileView _out: FileView {
        id: outFile
        path: bus._outPath
        atomicWrites: false
        printErrors: false
    }

    // throttle the 60fps cava stream down to ~20fps file writes
    property Timer _pump: Timer {
        interval: 50
        repeat: true
        running: bus.playing && bus.ready
        onTriggered: bus._writeOut()
    }

    // if frames stop coming (cava died, audio dropped) decay to not-ready
    property Timer _watchdog: Timer {
        interval: 500
        repeat: true
        running: bus.playing
        onTriggered: {
            if (bus._lastWall && Date.now() - bus._lastWall > 1500) {
                bus.ready = false; bus.silent = false
                bus.level = 0; bus.bass = 0; bus.mid = 0; bus.high = 0
                bus._envL = 0; bus._envB = 0; bus._envM = 0; bus._envH = 0
            }
        }
    }
}
