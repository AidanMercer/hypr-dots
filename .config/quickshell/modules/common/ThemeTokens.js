.pragma library

// The theme token keys and their stock values, in one place. ThemeConfig (popup
// and bar) and ThemePalette (injected into theme widgets) both parse config.toml
// through here so they can't drift. themes/default/config.toml carries the same
// values — these are only the fallback if that file is missing.
var BOOL_KEYS = { bubbles: false, cyber: false }
var COLOR_KEYS = {
    accent: "#a8b5e8",
    accent2: "#c8a5e8",
    accent3: "#e8919b",
    accent_warn: "#e8c89b",
    accent_dim: "#3b3f51",
    text: "#e6e6f0",
    glass: "#0f0f14",
}
var STRING_KEYS = { font_mono: "monospace", bar_position: "top" }

var DEFAULTS = (function () {
    var d = {}
    for (var k in BOOL_KEYS) d[k] = BOOL_KEYS[k]
    for (var c in COLOR_KEYS) d[c] = COLOR_KEYS[c]
    for (var s in STRING_KEYS) d[s] = STRING_KEYS[s]
    return d
})()

// Flat toml, last write wins — so catting default config + theme config layers
// them. Anchored per-key regexes, so `accent =` never swallows `accent2 =`.
function parse(text) {
    var out = {}
    for (var k in DEFAULTS) out[k] = DEFAULTS[k]
    var lines = (text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        for (var b in BOOL_KEYS) {
            var mb = line.match(new RegExp("^\\s*" + b + "\\s*=\\s*(true|false)\\b", "i"))
            if (mb) out[b] = mb[1].toLowerCase() === "true"
        }
        for (var c in COLOR_KEYS) {
            var mc = line.match(new RegExp("^\\s*" + c + "\\s*=\\s*[\"']?(#[0-9a-fA-F]{3,8})[\"']?", "i"))
            if (mc) out[c] = mc[1]
        }
        for (var s in STRING_KEYS) {
            var ms = line.match(new RegExp("^\\s*" + s + "\\s*=\\s*[\"']([^\"']*)[\"']"))
            if (ms) out[s] = ms[1]
        }
    }
    return out
}
