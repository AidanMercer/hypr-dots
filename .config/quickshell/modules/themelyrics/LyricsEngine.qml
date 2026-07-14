import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// The lyric ENGINE — every theme-independent part of the desktop lyric
// visualizer: MPRIS player selection, the interpolated position clock, the
// lyricvis-fetch.py fetch/cache handshake, live offset calibration, the cava
// silence detector, the beat clock, chorus detection, the album-art palette
// and the per-word karaoke timing model.
//
// ThemeLyrics owns one per monitor window and injects it into the active
// theme's lyrics.qml as `engine` (widgets declare `property var engine` —
// same grep-based handshake as `pal`). The theme file only decides how the
// words LOOK; everything it needs is on the surface below.
//
//   player, playing, estMs, lengthMs, fmt(ms)
//   lines, lyricsLoaded, lyricsSynced
//   activeIndex, tokens, tokenSpans, tokenState(i, est), lineDoneMs
//   chorusMask, isChorus(i), inChorus — lexical chorus detection for staging
//   nextLineStartMs, nextLineInMs, inInterlude — gap awareness / countdowns
//   audioReady, audioSilent, audioPulse, audioEnergy, audioEnergyAvg, audioLift
//   bpm, beatPhase, beatConfident (+ beat() signal) — cava-driven beat clock
//   trackPalette, trackPaletteReady, trackPrimary/trackVivid/trackDeep,
//     trackTint(base, amt) — album-art swatches for per-song color grading
//   offsetMs (+ offsetNudged() signal for a calibration OSD)
//   tuning: baseWordMs / perSyllableMs / holdCapMs — reset on every widget
//   mount (resetTuning), so one theme's tweak can't leak into the next
//
// `active` is wired by ThemeLyrics to "a widget that wants the engine is
// loaded" — everything with a running cost (timers, cava, fetches) is gated
// on it, so a theme without lyrics pays nothing.
QtObject {
    id: engine

    // wired by ThemeLyrics
    property bool active: false
    // True only on the primary-screen instance. Gates the single cava
    // silence-detector so the theme showing on multiple monitors doesn't
    // spawn one cava reader per screen.
    property bool isPrimary: false

    // an engine that wakes mid-track re-anchors and fetches for wherever the
    // player is now; stale lines from a previous activation never flash. The
    // audio feed freezes wherever it was when active drops, so reset it to the
    // fail-open baseline both ways — a reactivation mid-vocal must not release
    // held words off a silence flag frozen during some earlier instrumental gap.
    onActiveChanged: {
        audioSilent = false; audioReady = false; audioPulse = 0
        audioEnergy = 0; audioEnergyAvg = 0
        _env = 0; _pulseEnv = 0; _lastAudioWall = 0; _quietSinceWall = 0
        resetBeat()
        if (!active || !player) return
        hardAnchor()
        if (trackKey() !== loadedKey) { clearLyrics(); fetchDebounce.restart() }
    }

    // ---- player selection ---------------------------------------------------
    // Re-evaluates whenever the set of MPRIS players changes. Prefer spotifyd;
    // fall back to whatever's playing, then to the first player there is.
    property var player: pickPlayer(Mpris.players ? Mpris.players.values : [])

    function pickPlayer(list) {
        if (!list || list.length === 0) return null
        let playing = null
        let supported = null
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            const tag = ((p.dbusName || "") + " " + (p.identity || "")).toLowerCase()
            if (tag.indexOf("spotify") !== -1) return p
            if (!supported && p.positionSupported) supported = p
            if (!playing && p.isPlaying) playing = p
        }
        // prefer something actually playing, then anything that reports a position,
        // so a browser tab that exposes no position can't hijack the readout
        return playing || supported || list[0]
    }

    // ---- interpolation clock ------------------------------------------------
    property real anchorPosMs: 0          // last real position read off MPRIS
    property real anchorWall: Date.now()  // Date.now() when we read it
    property real estMs: 0                // smoothed estimate, updated at 30fps
    property bool anchored: false         // false until the first real position read
    readonly property real lengthMs: player ? player.length * 1000 : 0
    readonly property bool playing: player ? player.isPlaying : false

    // Audio-output latency offset (ms). estMs = reported position + offsetMs, so a
    // NEGATIVE value lights words LATER, in time with delayed (e.g. Bluetooth)
    // audio. Calibrated live by ear — the value is owned by shell.qml's lyricOffset
    // IPC handler and shared through a state file this instance watches (below).
    property int offsetMs: -250
    readonly property int offsetMin: -1500
    readonly property int offsetMax: 1500

    // Re-anchor smoothing. A fresh 1s position read rarely matches our extrapolation
    // exactly; instead of snapping estMs (a visible jump every second) we carry the
    // small disagreement as slewErr and bleed it off over a few ticks, keeping estMs
    // continuous. A big disagreement (real seek / stall / first read) snaps instead.
    readonly property int  slewMaxMs: 120
    readonly property real slewGain:  0.18
    property real slewErr: 0

    function reanchor() {
        if (!player) return
        const freshPos = player.position * 1000   // Quickshell computes position on read
        const now = Date.now()
        const predicted = anchorPosMs + (playing ? (now - anchorWall) : 0)
        const err = freshPos - predicted
        anchorPosMs = freshPos
        anchorWall = now
        if (!anchored || Math.abs(err) > slewMaxMs) {
            anchored = true
            slewErr = 0                           // snap: seek / stall / first read
        } else {
            slewErr = predicted - freshPos        // keep estMs continuous; decays to 0
        }
        tick()
    }

    // Force an immediate snap to truth (pause/resume — the position is reliable then).
    function hardAnchor() {
        if (!player) { resetAnchor(); return }
        anchorPosMs = player.position * 1000
        anchorWall = Date.now()
        anchored = true
        slewErr = 0
        tick()
    }

    // On a track change the player's last-known position is still the *previous*
    // track's for a beat, so don't trust it — zero out and let the 1s re-read catch
    // up. Worst case the readout starts at 0:00 and snaps to truth within a second.
    function resetAnchor() {
        anchorPosMs = 0
        anchorWall = Date.now()
        anchored = false
        slewErr = 0
        estMs = 0
    }

    function tick() {
        if (!player) { estMs = 0; return }
        let e = anchorPosMs + offsetMs            // offset applied ONCE, here
        if (playing) e += (Date.now() - anchorWall)
        if (slewErr !== 0) {                       // carry then decay the re-anchor error
            e += slewErr
            slewErr -= slewErr * slewGain
            if (Math.abs(slewErr) < 1) slewErr = 0
        }
        if (lengthMs > 0) e = Math.max(0, Math.min(e, lengthMs))
        estMs = e
        // beat phase rides the same 30fps tick; wall-clock based, since the
        // onsets are wall-stamped off the live audio (already latency-true)
        if (beatConfident && playing && audioReady) {
            const k = (Date.now() - _beatAnchor) / _beatPeriod
            beatPhase = k - Math.floor(k)
            if (Math.floor(k) > _beatN) { _beatN = Math.floor(k); beat() }
        } else if (beatPhase !== 0) beatPhase = 0
    }

    function fmt(ms) {
        if (ms < 0 || isNaN(ms)) ms = 0
        const t = Math.floor(ms / 1000)
        const m = Math.floor(t / 60)
        const s = t % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    onPlayerChanged: { resetAnchor(); clearLyrics(); fetchDebounce.restart() }
    Component.onCompleted: if (active && player) fetchDebounce.restart()

    // Re-read the authoritative position once a second; pause/resume and track
    // changes re-anchor immediately off their own signals. Quickshell computes
    // position live on read and never emits positionChanged itself, so a manual
    // scrub only re-syncs on the next 1s tick.
    property Timer _reanchorTimer: Timer {
        interval: 1000; repeat: true
        running: engine.active && engine.player !== null
        onTriggered: engine.reanchor()
    }
    property Timer _tickTimer: Timer {
        interval: 33; repeat: true
        running: engine.active && engine.playing
        onTriggered: engine.tick()
    }

    property Connections _playerConn: Connections {
        target: engine.player
        ignoreUnknownSignals: true
        function onIsPlayingChanged()  { engine.hardAnchor() }
        // Quickshell computes position lazily and only emits positionChanged on a
        // genuine seek/scrub, so this re-syncs a scrub immediately instead of waiting
        // for the next 1s tick. (A spurious emit just re-arms a ~0ms slew — harmless.)
        function onPositionChanged()   { engine.reanchor() }
        // title fires early (metadata still settling) — reset the display now;
        // postTrackChanged fires once metadata is coherent and drives the fetch.
        // The beat clock resets too: the next song's tempo is a fresh question.
        function onTrackTitleChanged() { engine.resetAnchor(); engine.clearLyrics(); engine.resetBeat(); fetchDebounce.restart() }
        function onPostTrackChanged()  { fetchDebounce.restart() }
    }

    // ---- lyrics fetch --------------------------------------------------------
    // [{t: ms, text}] for the current track, or [] if none / not yet loaded.
    property var lines: []
    property bool lyricsSynced: false
    property bool lyricsLoaded: false      // got an answer for the wanted track?
    property string wantKey: ""            // track we want lyrics for
    property string loadedKey: ""          // track currently displayed
    property string fetchingKey: ""        // track in flight ("" = idle)

    // Stable per-track key: prefer the spotify id from MPRIS metadata, else
    // title|artist. Dedupes fetches and (via the script) becomes the cache key.
    function trackKey() {
        if (!player) return ""
        let url = ""
        const m = player.metadata
        try { url = m ? (m["xesam:url"] || "") : "" } catch (e) { url = "" }
        if (url) {
            if (url.indexOf("spotify:track:") === 0) return url
            const i = url.indexOf("/track/")
            if (i !== -1) return "spotify:track:" + url.substring(i + 7).split("?")[0].split("/")[0]
        }
        return (player.trackTitle || "") + "|" + (player.trackArtist || "")
    }

    // Clear the displayed lyrics immediately on a track change so a stale line
    // from the previous song can never flash while the new fetch is in flight.
    // The art palette clears with it — a new song must not wear the old tint.
    function clearLyrics() {
        lines = []
        lyricsSynced = false
        lyricsLoaded = false
        loadedKey = ""
        fetchFails = 0
        trackPalette = null
        artLoadedKey = ""
    }

    function requestLyrics() {
        if (!player || !player.trackTitle) return
        wantKey = trackKey()
        pump()
        pumpArt()
    }

    // Start a fetch for wantKey unless we already have it or one's in flight.
    // Quickshell's Process.running=true is a no-op while running and won't adopt
    // a reassigned command, so we never reassign mid-flight — applyLyrics ends
    // with pump(), so a skip during a fetch isn't lost.
    function pump() {
        if (!active || !player) return
        if (fetchProc.running) return
        if (wantKey === "" || wantKey === loadedKey) return
        fetchingKey = wantKey
        // bash -c with --opt=value argv: $HOME expands, metadata passes safely as
        // argv (no shell injection), and '='-form survives titles starting with '-'
        fetchProc.command = [
            "bash", "-c",
            'exec python3 "$HOME/.config/quickshell/scripts/lyricvis-fetch.py" "$@"',
            "bash",
            "--id=" + wantKey,
            "--artist=" + (player.trackArtist || ""),
            "--title=" + (player.trackTitle || ""),
            "--album=" + (player.trackAlbum || ""),
            "--duration=" + String(Math.round(player.length || 0)),
        ]
        fetchProc.running = true
    }

    function applyLyrics(text) {
        let d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        // accept only a result for the track we still want — guards against a
        // late result for a track we've since skipped past, and empty output
        if (d && d.reqId === wantKey) {
            lines = d.lines || []
            lyricsSynced = !!d.synced
            lyricsLoaded = true
            loadedKey = wantKey
        }
        fetchingKey = ""
        // non-JSON means the fetch script itself died ("no lyrics" is still
        // JSON) — back off instead of pump() re-firing it in a tight loop
        if (d === null) {
            fetchFails++
            if (fetchFails < 3) fetchBackoff.restart()
            return
        }
        fetchFails = 0
        pump()   // wantKey may have moved on while we were fetching
    }

    property int fetchFails: 0
    property Timer _fetchBackoff: Timer {
        id: fetchBackoff
        interval: 15000; repeat: false
        onTriggered: engine.pump()
    }

    // Coalesce the title-change + postTrackChanged signals into one fetch, by
    // which point metadata (url/album/length) has settled.
    property Timer _fetchDebounce: Timer {
        id: fetchDebounce
        interval: 250; repeat: false
        onTriggered: engine.requestLyrics()
    }

    property Process _fetchProc: Process {
        id: fetchProc
        // applyLyrics() ends with pump(), so a skip that lands mid-fetch is
        // picked up when this run finishes.
        stdout: StdioCollector { onStreamFinished: engine.applyLyrics(text) }
    }

    // ---- album-art palette ----------------------------------------------------
    // lyricvis-art.py boils the current cover down to three swatches — dominant,
    // most-vivid, darkest — cached per track like the lyrics. Fully fail-open:
    // no art / no network / no ffmpeg -> trackPalette stays null, the convenience
    // colors fall back to neutral grays, and trackTint() is the identity. Themes
    // gate on trackPaletteReady (or just call trackTint, which is always safe).
    property var trackPalette: null
    property string artLoadedKey: ""
    readonly property bool trackPaletteReady: trackPalette !== null && trackPalette.ok === true
    readonly property color trackPrimary: trackPaletteReady ? trackPalette.c1 : "#8a8a8a"
    readonly property color trackVivid:   trackPaletteReady ? trackPalette.c2 : "#8a8a8a"
    readonly property color trackDeep:    trackPaletteReady ? trackPalette.c3 : "#3a3a3a"

    // blend a theme color toward the track's vivid swatch; amt 0..1
    function trackTint(base, amt) {
        if (!trackPaletteReady) return base
        return Qt.rgba(base.r + (trackVivid.r - base.r) * amt,
                       base.g + (trackVivid.g - base.g) * amt,
                       base.b + (trackVivid.b - base.b) * amt,
                       base.a)
    }

    function artUrlOf() {
        if (!player) return ""
        try { const m = player.metadata; return m ? (m["mpris:artUrl"] || "") : "" } catch (e) { return "" }
    }

    // same never-reassign-mid-flight discipline as pump(); applyArt ends with
    // pumpArt() so a skip during an extraction isn't lost. artUrl can settle a
    // beat after the title — postTrackChanged re-runs the debounce and we retry.
    function pumpArt() {
        if (!active || !player) return
        if (artProc.running) return
        if (wantKey === "" || wantKey === artLoadedKey) return
        const u = artUrlOf()
        if (u === "") return
        artProc.command = [
            "bash", "-c",
            'exec python3 "$HOME/.config/quickshell/scripts/lyricvis-art.py" "$@"',
            "bash",
            "--id=" + wantKey,
            "--url=" + u,
        ]
        artProc.running = true
    }

    function applyArt(text) {
        let d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        // an ok:false answer still sets artLoadedKey — one attempt per track view,
        // not a retry storm; the cache holds only good palettes so replays retry
        if (d && d.reqId === wantKey) {
            trackPalette = d
            artLoadedKey = wantKey
        }
        pumpArt()
    }

    property Process _artProc: Process {
        id: artProc
        stdout: StdioCollector { onStreamFinished: engine.applyArt(text) }
    }

    // ---- offset calibration (shared via shell.qml's lyricOffset IPC) ---------
    // shell.qml owns the live offset (one IPC handler, never duplicated) and writes
    // it to this state file; every per-monitor instance just WATCHES the file, so a
    // by-ear nudge re-syncs all screens at once and survives `qs kill; qs -d`.
    // Themes wanting an OSD hook offsetNudged() — it fires on every live nudge,
    // not on the initial load.
    signal offsetNudged()
    property bool offsetReady: false
    property FileView _offsetFile: FileView {
        id: offsetFile
        path: Quickshell.stateDir + "/lyric-offset"
        blockLoading: true
        preload: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: engine.applyOffset()
    }
    function applyOffset() {
        const v = parseInt(offsetFile.text().trim(), 10)
        if (!isNaN(v)) offsetMs = Math.max(offsetMin, Math.min(offsetMax, v))
        tick()
        if (offsetReady) offsetNudged()   // don't flash on the initial load
        offsetReady = true
    }

    // ---- audio-reactive feed: silence-aware hold release --------------------
    // PRIMARY instance only so 3 monitors don't spawn 3 cava readers. Its own
    // conf (autosens off) makes the energy ABSOLUTE, so a real instrumental gap
    // reads as silence and the end-of-line breath is released instead of glowing
    // through the gap. Fully fail-open: no feed -> audioReady stays false -> the
    // hold behaves exactly as before.
    property bool audioSilent: false
    property real audioPulse: 0
    property bool audioReady: false
    // full-band envelope, published for the themes: audioEnergy is the live
    // loudness (absolute, autosens off), audioEnergyAvg a ~4s rolling mean of
    // the raw frames. audioLift is the ratio — >1.2 reads as a hot section /
    // drop, <0.7 as a breakdown. All zero on non-primary screens (gate on
    // audioReady, like audioPulse).
    property real audioEnergy: 0
    property real audioEnergyAvg: 0
    readonly property real audioLift: audioEnergyAvg > 0.02 ? Math.min(3, audioEnergy / audioEnergyAvg) : 1
    property real _env: 0
    property real _pulseEnv: 0
    property real _lastAudioWall: 0
    property real _quietSinceWall: 0
    readonly property real silenceEnter: 0.040    // env below this counts as 'quiet'
    readonly property real silenceExit:  0.075    // must exceed this to count 'loud'
    readonly property int  silenceDebounceMs: 180

    function parseAudioFrame(line) {
        const parts = line.split(";")
        let sum = 0, cnt = 0, bass = 0, bn = 0
        for (let i = 0; i < parts.length; i++) {
            if (parts[i] === "") continue
            let v = parseInt(parts[i]) / 1000
            if (v < 0.05) v = 0                    // same noise floor as the reactor
            if (i > 0) { sum += v; cnt++ }         // skip bin 0 (DC-ish)
            if (i <= 2) { bass += v; bn++ }
        }
        if (cnt === 0) return
        const inst = sum / cnt
        const bassInst = bn ? bass / bn : 0
        _env = inst > _env ? _env + (inst - _env) * 0.6 : _env + (inst - _env) * 0.25
        _pulseEnv = bassInst > _pulseEnv ? _pulseEnv + (bassInst - _pulseEnv) * 0.7
                                         : _pulseEnv + (bassInst - _pulseEnv) * 0.35
        audioPulse = _pulseEnv
        _lastAudioWall = Date.now()
        audioReady = true
        const now = Date.now()
        audioEnergy = _env
        audioEnergyAvg += (inst - audioEnergyAvg) * 0.004
        // beat onset: the raw bass jumping clear of its own slow average reads
        // as a kick. Check against the average BEFORE folding this frame in,
        // debounced to < 240 BPM so one kick can't double-fire.
        if (bassInst > _bassAvg + 0.055 && bassInst > _bassAvg * 1.5
                && now - _lastOnsetWall > 250) {
            _lastOnsetWall = now
            _onsets.push(now)
            if (_onsets.length > 24) _onsets.shift()
            _retime()
        }
        _bassAvg += (bassInst - _bassAvg) * 0.05
        if (_env < silenceEnter) {
            if (_quietSinceWall === 0) _quietSinceWall = now
            if (now - _quietSinceWall >= silenceDebounceMs) audioSilent = true
        } else if (_env > silenceExit) {
            _quietSinceWall = 0
            audioSilent = false
        }
    }

    // ---- beat clock: bass onsets -> tempo -> phase ---------------------------
    // Inter-onset gaps folded into one tempo octave (80–160 BPM), medianed, and
    // phase-anchored to the latest kick. beatPhase saws 0..1 across each beat
    // (updates on the 30fps tick) and beat() fires on the wrap — themes quantize
    // pops/pulses to it so motion lands ON the music instead of near it. Fail-
    // open like the rest of the feed: no cava / no drums / inconsistent gaps ->
    // beatConfident stays false and beatPhase rests at 0.
    property real bpm: 0
    property real beatPhase: 0
    property bool beatConfident: false
    signal beat()
    property var _onsets: []
    property real _bassAvg: 0
    property real _lastOnsetWall: 0
    property real _beatPeriod: 0
    property real _beatAnchor: 0
    property real _beatN: 0

    function resetBeat() {
        _onsets = []
        beatConfident = false
        beatPhase = 0
        _bassAvg = 0
        _lastOnsetWall = 0
    }

    function _retime() {
        const o = _onsets
        if (o.length < 5) { beatConfident = false; return }
        let per = []
        for (let i = 1; i < o.length; i++) {
            let g = o[i] - o[i - 1]
            if (g < 200 || g > 3000) continue      // dropouts / long rests
            while (g < 375) g *= 2                 // fold into 80–160 BPM
            while (g > 750) g /= 2
            per.push(g)
        }
        if (per.length < 4) { beatConfident = false; return }
        per.sort(function (a, b) { return a - b })
        const med = per[per.length >> 1]
        let sum = 0, n = 0
        for (let i = 0; i < per.length; i++)
            if (Math.abs(per[i] - med) < med * 0.12) { sum += per[i]; n++ }
        // most gaps must agree with the median or this isn't a groove
        if (n < Math.max(4, per.length * 0.6)) { beatConfident = false; return }
        _beatPeriod = sum / n
        bpm = Math.round(60000 / _beatPeriod)
        _beatAnchor = o[o.length - 1]
        _beatN = 0
        beatConfident = true
    }

    property Process _audioCava: Process {
        id: audioCava
        // playing too — a paused player doesn't need a 60fps capture stream;
        // frame-stop decays audioReady below, which is the designed fail-open
        running: engine.active && engine.isPrimary && engine.playing
        command: ["cava", "-p", Qt.resolvedUrl("cava-lyrics.conf").toString().replace("file://", "")]
        stdout: SplitParser { onRead: line => engine.parseAudioFrame(line) }
        onRunningChanged: if (engine.active && engine.isPrimary && engine.playing && !running) audioCavaRestart.start()
    }
    property Timer _audioCavaRestart: Timer {
        id: audioCavaRestart
        interval: 2000
        // re-assign the BINDING, never `running = true`: an imperative write
        // would strip the active/isPrimary gate off this long-lived object, so
        // one cava crash could leak a 60fps reader past deactivation forever
        onTriggered: audioCava.running = Qt.binding(() => engine.active && engine.isPrimary && engine.playing)
    }
    // If frames stop (cava died, not yet restarted), decay to not-ready so the
    // feature fails open rather than holding a stale 'silent'.
    property Timer _audioDecay: Timer {
        interval: 500; repeat: true
        running: engine.active && engine.isPrimary
        onTriggered: {
            if (engine._lastAudioWall && Date.now() - engine._lastAudioWall > 1500) {
                engine.audioReady = false; engine.audioPulse = 0; engine.audioSilent = false
                engine.audioEnergy = 0; engine.beatConfident = false; engine.beatPhase = 0
            }
        }
    }

    // ---- active line / word --------------------------------------------------
    // Index of the last line whose timestamp is <= the smoothed clock, or -1
    // before the first line. Re-evaluates as estMs ticks.
    readonly property int activeIndex: {
        const L = lines
        const ms = estMs
        if (!L || L.length === 0 || ms < L[0].t) return -1
        let lo = 0, hi = L.length - 1, ans = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (L[mid].t <= ms) { ans = mid; lo = mid + 1 } else hi = mid - 1
        }
        return ans
    }

    function lineText(i) {
        return (i >= 0 && lines[i]) ? (lines[i].text || "") : ""
    }
    function lineEnd(i) {
        if (i + 1 < lines.length) return lines[i + 1].t
        // last line: hold until track end, but guard a stale/short length that
        // would collapse the span (then the line would snap through instantly)
        if (lines[i] && lengthMs > lines[i].t) return lengthMs
        return lines[i] ? lines[i].t + 4000 : 0
    }

    // ---- song structure: chorus detection -------------------------------------
    // A line is chorus when its normalized text repeats elsewhere in the song AND
    // it sits in a run of repeated lines (or is a many-times hook on its own).
    // Purely lexical — a staging hint, not ground truth. Songs where nearly
    // everything repeats get an all-false mask: no verse/chorus contrast to stage.
    // NOTE for themes: reference `chorusMask` (not just isChorus()) in a binding
    // that must re-evaluate when the lyrics land.
    function _normLine(s) {
        return (s || "").toLowerCase()
            .replace(/[.,!?;:"“”‘’„«»()\[\]{}\-—–…~*]+/g, " ")
            .replace(/\s+/g, " ").trim()
    }
    readonly property var chorusMask: {
        const L = lines
        if (!L || L.length < 6) return []
        const counts = {}
        const norms = new Array(L.length)
        for (let i = 0; i < L.length; i++) {
            const n = _normLine(L[i].text)
            norms[i] = n
            if (n.length >= 6) counts[n] = (counts[n] || 0) + 1
        }
        const rep = new Array(L.length)
        for (let i = 0; i < L.length; i++)
            rep[i] = norms[i].length >= 6 && counts[norms[i]] >= 2
        const mask = new Array(L.length)
        let total = 0
        for (let i = 0; i < L.length; i++) {
            mask[i] = rep[i] === true
                && ((i > 0 && rep[i - 1]) || (i + 1 < L.length && rep[i + 1])
                    || counts[norms[i]] >= 4)
            if (mask[i]) total++
        }
        if (total === 0 || total > L.length * 0.7) return new Array(L.length).fill(false)
        return mask
    }
    function isChorus(i) {
        const m = chorusMask
        return i >= 0 && i < m.length && m[i] === true
    }
    readonly property bool inChorus:
        activeIndex >= 0 && activeIndex < chorusMask.length && chorusMask[activeIndex] === true

    // ---- gap awareness: what's coming ------------------------------------------
    // nextLineInMs counts down to the next vocal (also before the first line), so
    // themes can stage a karaoke-style countdown. inInterlude flags a real
    // instrumental break — current line done and > 4.5s of dead air (intro and
    // outro included) — the theme's cue to recede and play something ambient.
    readonly property real nextLineStartMs: {
        const L = lines
        const i = activeIndex + 1
        return (L && i >= 0 && i < L.length) ? L[i].t : -1
    }
    readonly property real nextLineInMs:
        nextLineStartMs >= 0 ? Math.max(0, nextLineStartMs - estMs) : -1
    readonly property bool inInterlude: {
        if (!lyricsSynced || lines.length === 0) return false
        if (activeIndex < 0) return lines[0].t > 4500 && estMs < lines[0].t
        const gapEnd = nextLineStartMs >= 0 ? nextLineStartMs : lengthMs
        return estMs > lineDoneMs && (gapEnd - lineDoneMs) > 4500
    }

    // ---- token model: main vocal vs background adlib -------------------------
    // One ordered list of tokens {text, bg, mainIdx, t, d} for the active line.
    // The fetcher's per-line words[] is authoritative (adlibs already split out,
    // real onsets when it's a word-level source). If a stale pre-words[] cache file
    // is loaded we paren-split the text ourselves with the SAME rules. Background
    // adlibs (bg) are kept in source order so each anchors to the word it follows,
    // and carry zero main-vocal timing budget.
    function buildTokens(i) {
        if (i < 0 || !lines[i]) return []
        const w = lines[i].words
        if (w !== undefined && w !== null) {        // fetcher authoritative (may be [])
            let out = [], mi = 0
            for (let k = 0; k < w.length; k++) {
                const bg = !!w[k].bg
                out.push({ text: w[k].text, bg: bg, mainIdx: bg ? -1 : mi++,
                           t: (w[k].t || 0), d: (w[k].d || 0) })
            }
            return out
        }
        // FALLBACK for stale cache without words[]: paren-split here, mirroring the
        // fetcher (drop pure punctuation + (x4)-style markers; promote all-adlib lines).
        const txt = lineText(i)
        let all = [], mainCount = 0
        const re = /\(([^)]*)\)|([^\s()]+)/g
        let m
        while ((m = re.exec(txt)) !== null) {
            if (m[1] !== undefined) {
                const inner = m[1].trim()
                if (inner.length && !/^\s*(?:x\s*\d+|\d+\s*x|repeat)/i.test(inner))
                    all.push({ text: inner, bg: true })
            } else if (!/^[^0-9A-Za-z'’]+$/.test(m[2])) {
                all.push({ text: m[2], bg: false }); mainCount++
            }
        }
        if (all.length && mainCount === 0) for (let k = 0; k < all.length; k++) all[k].bg = false
        let out = [], mi = 0
        for (let k = 0; k < all.length; k++)
            out.push({ text: all[k].text, bg: all[k].bg, mainIdx: all[k].bg ? -1 : mi++, t: 0, d: 0 })
        return out
    }

    readonly property var tokens: buildTokens(activeIndex)

    // ---- per-token timing: real onsets, else capped syllable stretch --------
    // Tuning a theme may tweak after mount; resetTuning() restores the defaults
    // before every widget mount so a tweak can't leak across themes.
    property int baseWordMs: 60         // fixed per-word cost
    property int perSyllableMs: 220     // added per syllable (lower = faster sweep)
    property int holdCapMs: 1500        // max end-of-line breath before settling
    function resetTuning() {
        baseWordMs = 60
        perSyllableMs = 220
        holdCapMs = 1500
    }
    // The estimate spreads onsets across the line span, but never further than the
    // words could *naturally* fill — so a line followed by an instrumental gap
    // doesn't smear its last words out into the dead air.
    readonly property real stretchSlack: 1.5

    // Real per-word timing for line i? True if any word carries a duration or a
    // distinct onset (LRCLIB line-level gives every word the same line timestamp).
    function lineWordLevel(i) {
        const L = lines[i]
        if (!L || !L.words) return false
        for (let k = 0; k < L.words.length; k++) {
            const w = L.words[k]
            if (w.d > 0 || (w.t !== undefined && w.t !== L.t)) return true
        }
        return false
    }

    function syllables(word) {
        const w = word.toLowerCase().replace(/[^a-z]/g, "")
        if (!w.length) return 1
        const m = w.match(/[aeiouy]+/g)
        let n = m ? m.length : 1
        if (w.length > 2 && w.charAt(w.length - 1) === "e"
            && "aeiouy".indexOf(w.charAt(w.length - 2)) === -1) n -= 1   // silent e
        return Math.max(1, n)
    }

    // [{start, fillEnd, end}] ms per token. Real path: pass each onset (and onset+d,
    // or a short default) straight through. Estimate path: MAIN tokens are spread by
    // syllable weight across a capped span (not packed at the front); each bg adlib
    // hangs briefly off the main word it follows (zero main budget); the last main
    // word absorbs trailing slack as a capped breath. Recomputed on line change only.
    readonly property var tokenSpans: {
        const ai = activeIndex, tk = tokens
        if (ai < 0 || tk.length === 0) return []
        const start = lines[ai].t
        const rawEnd = lineEnd(ai)
        let out = new Array(tk.length)

        if (lineWordLevel(ai)) {
            for (let i = 0; i < tk.length; i++) {
                const t = tk[i].t
                let nxt = rawEnd
                for (let j = i + 1; j < tk.length; j++) { if (tk[j].t > t) { nxt = tk[j].t; break } }
                const fe = tk[i].d > 0 ? t + tk[i].d : Math.min(nxt, t + 600)
                out[i] = { start: t, fillEnd: fe, end: fe }
            }
            return out
        }

        let syl = [], totalSyl = 0, naturalTotal = 0
        for (let i = 0; i < tk.length; i++) {
            const s = tk[i].bg ? 0 : syllables(tk[i].text)
            syl.push(s); totalSyl += s
            if (!tk[i].bg) naturalTotal += baseWordMs + perSyllableMs * s
        }
        totalSyl = Math.max(1, totalSyl)
        const span = Math.max(1, rawEnd - start)
        const effSpan = Math.min(span, Math.max(naturalTotal * stretchSlack, 1))
        let cum = 0, lastMain = -1
        for (let i = 0; i < tk.length; i++) {
            if (tk[i].bg) continue
            const onset = start + effSpan * (cum / totalSyl)
            cum += syl[i]
            const slice = effSpan * (syl[i] / totalSyl)
            const natural = baseWordMs + perSyllableMs * syl[i]
            out[i] = { start: onset, fillEnd: onset + Math.min(slice, natural), end: onset + slice }
            lastMain = i
        }
        for (let i = 0; i < tk.length; i++) {
            if (!tk[i].bg) continue
            let a = start
            for (let j = i - 1; j >= 0; j--) if (!tk[j].bg && out[j]) { a = out[j].fillEnd; break }
            out[i] = { start: a, fillEnd: a + 250, end: Math.min(rawEnd, a + 700) }
        }
        if (lastMain >= 0)
            out[lastMain].end = Math.max(out[lastMain].fillEnd,
                Math.min(rawEnd, out[lastMain].fillEnd + holdCapMs))
        return out
    }

    // when the active line's last word (incl. its breath) ends — themes use it
    // to fade a finished line out instead of lingering through a long gap
    readonly property real lineDoneMs: {
        const sp = tokenSpans
        let mx = 0
        for (let i = 0; i < sp.length; i++) if (sp[i].end > mx) mx = sp[i].end
        return mx
    }

    // Per-token render state at time `est`: fill 0..1 plus active/sustain phase.
    // est is engine.estMs, which ALREADY includes offsetMs (applied once in tick())
    // — do NOT re-add it. A held word releases early to 'sung' when the mix has
    // gone genuinely silent (fail-open: only with a live audio feed while playing).
    // NOTE for themes: also touch audioSilent in the calling binding so a held-word
    // release re-evaluates the instant the silence signal flips.
    function tokenState(i, est) {
        const sp = tokenSpans
        if (i < 0 || i >= sp.length) return { fill: 0, active: false, sustain: false }
        const s = sp[i].start, fe = sp[i].fillEnd, e = sp[i].end
        if (est >= e) return { fill: 1, active: false, sustain: false }   // already sung
        if (est < s)  return { fill: 0, active: false, sustain: false }   // upcoming
        if (est < fe && fe > s) return { fill: (est - s) / (fe - s), active: true, sustain: false }
        if (audioReady && playing && audioSilent) return { fill: 1, active: false, sustain: false }
        return { fill: 1, active: true, sustain: true }                   // held: breathing
    }
}
