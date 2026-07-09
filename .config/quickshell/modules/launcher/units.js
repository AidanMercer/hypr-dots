.pragma library

// tiny unit converter for the launcher. everything in a category is stored as a
// factor to that category's base unit; convert = value * fromFactor / toFactor.
// temperature is the odd one out (offsets, not just scale) so it's handled apart.

const LENGTH = {  // base: metre
    mm: 0.001, cm: 0.01, dm: 0.1, m: 1, km: 1000,
    inch: 0.0254, in: 0.0254, "\"": 0.0254,
    ft: 0.3048, foot: 0.3048, feet: 0.3048, "'": 0.3048,
    yd: 0.9144, yard: 0.9144, yards: 0.9144,
    mi: 1609.344, mile: 1609.344, miles: 1609.344,
    nmi: 1852, ly: 9.4607304725808e15,
}
const MASS = {  // base: gram
    mg: 0.001, g: 1, gram: 1, grams: 1, kg: 1000, kilo: 1000, kilos: 1000,
    t: 1e6, tonne: 1e6, ton: 1e6,
    oz: 28.349523125, ounce: 28.349523125,
    lb: 453.59237, lbs: 453.59237, pound: 453.59237, pounds: 453.59237,
    st: 6350.29318, stone: 6350.29318,
}
const DATA = {  // base: byte  (decimal kb/mb, binary kib/mib)
    b: 1, byte: 1, bytes: 1,
    kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, pb: 1e15,
    kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776,
}
const TIME = {  // base: second
    ms: 0.001, s: 1, sec: 1, secs: 1, second: 1, seconds: 1,
    min: 60, mins: 60, minute: 60, minutes: 60,
    h: 3600, hr: 3600, hrs: 3600, hour: 3600, hours: 3600,
    d: 86400, day: 86400, days: 86400,
    wk: 604800, week: 604800, weeks: 604800,
    month: 2629800, months: 2629800, yr: 31557600, year: 31557600, years: 31557600,
}
const SPEED = {  // base: m/s
    mps: 1, "m/s": 1,
    kmh: 0.2777777778, kph: 0.2777777778, "km/h": 0.2777777778,
    mph: 0.44704, fps: 0.3048, knot: 0.514444, knots: 0.514444, kn: 0.514444,
}
const VOLUME = {  // base: litre
    ml: 0.001, cl: 0.01, dl: 0.1, l: 1, litre: 1, litres: 1, liter: 1, liters: 1,
    gal: 3.785411784, gallon: 3.785411784, gallons: 3.785411784,
    qt: 0.946352946, quart: 0.946352946, pt: 0.473176473, pint: 0.473176473,
    cup: 0.2365882365, cups: 0.2365882365,
    floz: 0.0295735296, tbsp: 0.0147867648, tsp: 0.00492892159,
}
const CATS = [
    { name: "length", tbl: LENGTH },
    { name: "mass", tbl: MASS },
    { name: "data", tbl: DATA },
    { name: "time", tbl: TIME },
    { name: "speed", tbl: SPEED },
    { name: "volume", tbl: VOLUME },
]

// temperature aliases -> canonical c/f/k
const TEMP = {
    c: "c", "°c": "c", celsius: "c", centigrade: "c",
    f: "f", "°f": "f", fahrenheit: "f",
    k: "k", kelvin: "k",
}
function tempToC(v, u) {
    if (u === "c") return v
    if (u === "f") return (v - 32) * 5 / 9
    return v - 273.15                      // k
}
function tempFromC(v, u) {
    if (u === "c") return v
    if (u === "f") return v * 9 / 5 + 32
    return v + 273.15                      // k
}

function findCat(u) {
    for (const c of CATS)
        if (u in c.tbl) return c
    return null
}

function fmt(n) {
    if (!isFinite(n)) return String(n)
    // trim to something human: up to 6 sig-ish digits, no trailing zero noise
    const r = Math.abs(n) >= 1e6 || (Math.abs(n) < 1e-4 && n !== 0)
        ? n.toPrecision(6)
        : String(Math.round(n * 1e6) / 1e6)
    return String(parseFloat(r))
}

// parse "10 km to mi", "72f in c", "5ft cm". with loose=false a separator word
// (to/in/as) is required, so plain app queries don't accidentally look like
// conversions; the `u ` prefix passes loose=true for the shorthand form.
function convert(raw, loose) {
    let s = (raw || "").trim().toLowerCase()
    if (!s) return null
    // number, then two unit tokens with an optional to/in/as/-> between them
    const sep = "(?:\\s+(?:to|in|as|into)\\s+|\\s*(?:->|>|=)\\s*|\\s+)"
    const re = new RegExp("^([+-]?[0-9]*\\.?[0-9]+)\\s*([a-z°\"'\\/]+)" + sep + "([a-z°\"'\\/]+)$")
    const m = s.match(re)
    if (!m) return null
    const val = parseFloat(m[1])
    const from = m[2], to = m[3]
    const hadWord = /\b(?:to|in|as|into)\b|->|>|=/.test(s)
    if (!loose && !hadWord) return null

    // temperature
    if (from in TEMP && to in TEMP) {
        const out = tempFromC(tempToC(val, TEMP[from]), TEMP[to])
        return { value: out, from: from, to: to,
                 text: fmt(val) + "°" + TEMP[from].toUpperCase() + " = " + fmt(out) + "°" + TEMP[to].toUpperCase(),
                 copy: fmt(out) }
    }
    const cf = findCat(from), ct = findCat(to)
    if (!cf || !ct || cf.name !== ct.name) return null
    const out = val * cf.tbl[from] / ct.tbl[to]
    return { value: out, from: from, to: to,
             text: fmt(val) + " " + from + " = " + fmt(out) + " " + to,
             copy: fmt(out) }
}
