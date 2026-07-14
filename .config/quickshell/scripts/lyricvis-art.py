#!/usr/bin/env python3
"""Album-art palette for the desktop lyric visualizer.

Sibling of lyricvis-fetch.py: given a track key and its MPRIS artUrl, boil the
cover down to three swatches the themes can color-grade with — c1 dominant,
c2 most-vivid, c3 darkest — and print one JSON object stamped with reqId
(same late-result guard as the lyric fetch). Good results cache under
~/.cache/lyricvis/art-<key>.json; failures are NOT cached, so they retry.

No Pillow on purpose — ffmpeg (already a rice dependency for the video
wallpapers) decodes the cover to a 32x32 raw RGB block and the quantizing is
plain python: 3-bit/channel buckets with mean colors, then pick swatches.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

CACHE_DIR = os.path.expanduser("~/.cache/lyricvis")
UA = "lyricvis/0.1 (https://github.com/AidanMercer/world80)"
SIZE = 32  # decode size; 1024 px is plenty for three swatches


def cache_key(id_, url):
    # mirror lyricvis-fetch's sanitizing so both caches key the same way
    if id_:
        k = re.sub(r"[^A-Za-z0-9_.-]", "_", id_)
        if k:
            return k
    return "h" + hashlib.sha1((url or "").encode()).hexdigest()[:16]


def emit(obj, reqid):
    obj = dict(obj)
    obj["reqId"] = reqid
    sys.stdout.write(json.dumps(obj))


def resolve(url):
    """URL -> (local path, is_temp). Handles file://, http(s) and bare paths."""
    if url.startswith("file://"):
        return urllib.parse.unquote(urllib.parse.urlparse(url).path), False
    if url.startswith(("http://", "https://")):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=12) as r:
            data = r.read()
        fd, tmp = tempfile.mkstemp(prefix="lyricvis-art-")
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return tmp, True
    if os.path.isfile(url):
        return url, False
    raise ValueError("unusable artUrl")


def pixels(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path,
         "-vf", f"scale={SIZE}:{SIZE}:flags=area",
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, timeout=15).stdout
    need = SIZE * SIZE * 3
    if len(raw) < need:
        raise ValueError("ffmpeg decode failed")
    return raw[:need]


def hexc(s):
    return "#%02x%02x%02x" % (s["r"], s["g"], s["b"])


def scaled(s, k):
    return {"r": min(255, round(s["r"] * k)),
            "g": min(255, round(s["g"] * k)),
            "b": min(255, round(s["b"] * k))}


def swatches(px):
    buckets = {}
    for i in range(0, len(px), 3):
        r, g, b = px[i], px[i + 1], px[i + 2]
        k = (r >> 5, g >> 5, b >> 5)
        c, sr, sg, sb = buckets.get(k, (0, 0, 0, 0))
        buckets[k] = (c + 1, sr + r, sg + g, sb + b)
    sw = []
    for c, sr, sg, sb in buckets.values():
        r, g, b = sr // c, sg // c, sb // c
        mx, mn = max(r, g, b), min(r, g, b)
        sw.append({"n": c, "r": r, "g": g, "b": b,
                   "sat": 0.0 if mx == 0 else (mx - mn) / mx,
                   "lum": 0.2126 * r + 0.7152 * g + 0.0722 * b})
    sw.sort(key=lambda s: -s["n"])
    body = [s for s in sw if s["n"] >= SIZE * SIZE * 0.01]  # ≥ ~10 px of cover

    # c1 dominant: the biggest patch that isn't blown white / crushed black
    c1 = next((s for s in body if 18 < s["lum"] < 240), sw[0])
    # c2 vivid: saturation-weighted among mid-lum patches — the tint color
    cand = [s for s in body if s["sat"] >= 0.25 and 30 < s["lum"] < 230]
    c2 = max(cand, key=lambda s: s["sat"] * (s["n"] ** 0.5)) if cand else c1
    # keep the tint usable: pull a too-dark/too-hot vivid into a workable band
    if c2["lum"] > 1 and c2["lum"] < 55:
        c2 = {**c2, **scaled(c2, 55 / c2["lum"])}
    elif c2["lum"] > 215:
        c2 = {**c2, **scaled(c2, 215 / c2["lum"])}
    # c3 deep: the darkest patch that still covers real area
    darks = [s for s in body if s["lum"] < c1["lum"]]
    c3 = min(darks, key=lambda s: s["lum"]) if darks else {**c1, **scaled(c1, 0.35)}
    return hexc(c1), hexc(c2), hexc(c3)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--id", default="")
    p.add_argument("--url", default="")
    p.add_argument("--force", action="store_true")
    a = p.parse_args()

    key = cache_key(a.id, a.url)
    path = os.path.join(CACHE_DIR, "art-" + key + ".json")

    if not a.force and os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                cached = json.load(f)
            if cached.get("ok"):
                emit(cached, a.id)
                return
        except (OSError, ValueError):
            pass

    tmp_path, is_temp = None, False
    try:
        if not a.url:
            raise ValueError("no artUrl")
        tmp_path, is_temp = resolve(a.url)
        c1, c2, c3 = swatches(pixels(tmp_path))
        result = {"id": key, "ok": True, "c1": c1, "c2": c2, "c3": c3}
    except Exception as e:
        emit({"id": key, "ok": False, "error": str(e)}, a.id)
        return
    finally:
        if is_temp and tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    # cache atomically, like the lyric fetch — never a torn sticky hit
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(result))
        os.replace(tmp, path)
    except OSError:
        pass
    emit(result, a.id)


if __name__ == "__main__":
    main()
