pragma Singleton
import QtQuick

QtObject {
    // When the active theme opts into cyberpunk chrome (config.toml: cyber = true),
    // the accent-bearing colors below retint to the theme's neon palette so the
    // shared control-popup tabs (Network/Sound/Bluetooth/Power/Display) match the
    // moon HUD without per-tab edits. Everything is gated on ThemeConfig.cyber, so
    // glass themes are byte-for-byte unaffected. ThemeConfig hardcodes its own
    // defaults (no Theme import), so there is no singleton cycle here.
    readonly property bool cyber: ThemeConfig.cyber
    readonly property color neon: ThemeConfig.accent
    readonly property color cyan: ThemeConfig.accent2
    readonly property color magenta: ThemeConfig.accent3
    readonly property color amber: ThemeConfig.accentWarn

    readonly property color glassBg: Qt.rgba(0.06, 0.06, 0.08, 0.62)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.24)
    readonly property color glassHighlight: Qt.rgba(1, 1, 1, 0.10)

    readonly property color rowHover: cyber ? Qt.rgba(cyan.r, cyan.g, cyan.b, 0.07) : Qt.rgba(1, 1, 1, 0.04)
    readonly property color rowSelected: cyber ? Qt.rgba(neon.r, neon.g, neon.b, 0.15) : Qt.rgba(1, 1, 1, 0.09)
    readonly property color divider: cyber ? Qt.rgba(cyan.r, cyan.g, cyan.b, 0.22) : Qt.rgba(1, 1, 1, 0.06)
    readonly property color dotBorder: cyber ? Qt.rgba(cyan.r, cyan.g, cyan.b, 0.45) : Qt.rgba(1, 1, 1, 0.22)
    readonly property color occupiedFill: Qt.rgba(1, 1, 1, 0.08)
    readonly property color subtleDivider: cyber ? Qt.rgba(cyan.r, cyan.g, cyan.b, 0.35) : Qt.rgba(1, 1, 1, 0.15)
    readonly property color trackBg: cyber ? Qt.rgba(neon.r, neon.g, neon.b, 0.10) : Qt.rgba(1, 1, 1, 0.08)
    readonly property color trackBg2: cyber ? Qt.rgba(cyan.r, cyan.g, cyan.b, 0.14) : Qt.rgba(1, 1, 1, 0.10)

    readonly property color textPrimary: "#e6e6f0"
    readonly property color textBright: "#ffffff"
    readonly property color textSecondary: "#c4c4d0"
    readonly property color textTertiary: "#d4d4dc"
    readonly property color textMuted: "#a0a4b0"
    readonly property color textDim: "#a8acb6"

    readonly property color accent: cyber ? neon : "#a8b5e8"
    readonly property color danger: cyber ? magenta : "#e8919b"
    readonly property color warning: cyber ? amber : "#e8c89b"
    readonly property color dangerHover: cyber ? Qt.rgba(magenta.r, magenta.g, magenta.b, 0.16) : Qt.rgba(0.91, 0.45, 0.50, 0.13)
    readonly property color volGradStart: cyber ? neon : "#8a99e8"
    readonly property color volGradEnd: cyber ? cyan : "#c8a5e8"
    readonly property color volGradMuteStart: "#555"
    readonly property color volGradMuteEnd: "#666"
    readonly property color thumbBorder: cyber ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.25)

    readonly property int barHeight: 44
    readonly property int bubbleHeight: 32
    readonly property int bubbleRadius: 16
    readonly property int popupRadius: 20

    // match the moon HUD's mono face when cyber; harmless fallback otherwise
    readonly property string mono: cyber ? "Noto Sans Mono" : "monospace"
    readonly property string icon: "Symbols Nerd Font"
}
