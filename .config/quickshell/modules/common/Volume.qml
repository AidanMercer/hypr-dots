pragma Singleton
import QtQuick

// Master output volume limits, shared by the only two places that write it: the
// OSD (XF86 volume keys, over IPC) and the Sound tab's slider.
//
// `max` sits above unity on purpose. This laptop's ALC245 has no board-specific
// kernel quirk (the codec matches only the generic HP vendor entry) and Linux
// has none of the vendor DSP that Windows runs ahead of the codec, so 100% is
// already the hardware flat out — see `pactl list sinks`: base volume 0.00 dB.
// Everything past unity is Pipewire software gain, which is the only headroom
// left. It clips on loud material, hence the cap rather than an open ceiling.
QtObject {
    // 1.0 = 100%. Anything above is software gain on top of a maxed-out codec.
    // 150% is the comfortable sitting point on these speakers, so the ceiling is
    // set above it rather than at it — the top of the range will clip on loud
    // material, which is why the gauge turns warning-coloured past unity.
    readonly property real max: 2.0
    readonly property real step: 0.05

    function clamp(v) { return Math.max(0, Math.min(max, v)) }
}
