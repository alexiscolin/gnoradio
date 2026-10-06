#!/usr/bin/env python3
"""GnoRadio launch-catalog curation pipeline (standard library only).

  curate.py fetch  [--seeds seeds.json] [--only SRC[,SRC]] [--seed ID] [--max-items N] [--include-review]
  curate.py hash   [--max N]                 sha256 (+ LUFS if ffmpeg) for non-Audius candidates
  curate.py batch  [--approved approved.json] build import_batch.json for catalog.ImportTrack

Rule: every track comes from a whitelisted seed (seeds.json). Never open-ended search.
"""
import argparse
import hashlib
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = "GnoRadioCurate/0.1 (+https://gno.land; catalog curation, whitelist only)"
APP = "GnoRadio"
AUDIUS = "https://api.audius.co/v1"

GENRES = {1: "Electronic", 2: "Synthwave", 3: "Ambient", 4: "Techno & House", 5: "Lo-fi & Chill",
          6: "Hip-hop & Beats", 7: "Rock & Indie", 8: "Pop", 9: "Jazz & Soul", 10: "Folk & Acoustic",
          11: "Cinematic & Classical", 12: "World"}
TARGET_PER_GENRE = 80

MIN_SEC, MAX_SEC = 90, 600
MIN_KBPS = 128      # hard floor (many good archive.org releases are VBR ~130-190 kbps)
WARN_KBPS = 192     # below this the candidate is flagged low_bitrate for the reviewer

# Audius genre -> GnoRadio genre id (first match wins; checked on lowercase).
AUDIUS_GENRES = [
    ("synthwave", 2), ("ambient", 3), ("techno", 4), ("house", 4), ("lo-fi", 5), ("lofi", 5),
    ("chill", 5), ("hip-hop", 6), ("rap", 6), ("trap", 6), ("beats", 6), ("rock", 7), ("alternative", 7),
    ("punk", 7), ("pop", 8), ("jazz", 9), ("soul", 9), ("r&b", 9), ("funk", 9), ("folk", 10),
    ("acoustic", 10), ("country", 10), ("classical", 11), ("soundtrack", 11), ("cinematic", 11),
    ("world", 12), ("latin", 12), ("reggae", 12), ("afro", 12), ("electronic", 1), ("dubstep", 1),
    ("drum & bass", 1), ("trance", 1), ("experimental", 1),
]

_last_call = {}

# ccMixter answers with a header line longer than http.client's 64 KiB default.
http.client._MAXLINE = 1 << 20


def http_json(url, host_delay=1.0):
    """GET a JSON document politely: one request per host per host_delay seconds."""
    host = urllib.parse.urlparse(url).netloc
    wait = _last_call.get(host, 0) + host_delay - time.time()
    if wait > 0:
        time.sleep(wait)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                _last_call[host] = time.time()
                return json.loads(r.read().decode("utf-8", "replace"), strict=False)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            raise
        except urllib.error.URLError:
            if attempt < 2:
                time.sleep(3)
                continue
            raise


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def save(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def clock(sec):
    sec = int(round(sec))
    return "%d:%02d" % (sec // 60, sec % 60)


def parse_len(v):
    """archive.org 'length' is seconds ('413.05') or a clock ('6:53', '1:02:03')."""
    if v is None:
        return None
    v = str(v).strip()
    try:
        if ":" in v:
            sec = 0.0
            for part in v.split(":"):
                sec = sec * 60 + float(part)
            return sec
        return float(v)
    except ValueError:
        return None


LIC_RE = re.compile(r"creativecommons\.org/(licenses|publicdomain)/([a-z-]+)/([0-9.]+)(?:/([a-z]{2}))?", re.I)


def spdx_license(url):
    """Map a Creative Commons URL to (SPDX id, port) or (None, reason). Only CC0, BY, BY-SA pass."""
    if not url:
        return None, "no license"
    m = LIC_RE.search(url)
    if not m:
        return None, "unknown license " + url
    kind, code, ver, port = m.group(1).lower(), m.group(2).lower(), m.group(3), m.group(4)
    if kind == "publicdomain":
        if code == "zero":
            return "CC0-1.0", None
        return None, "public domain mark (not a license)"
    if code == "by":
        spdx = "CC-BY-" + ver
    elif code == "by-sa":
        spdx = "CC-BY-SA-" + ver
    else:
        return None, "excluded license CC " + code.upper()
    if port:
        spdx += "-" + port.upper()
    return spdx, None


def attribution(title, artist, license_name, license_url, source_url):
    s = '"%s" by %s, licensed under %s' % (title, artist, license_name)
    if license_url:
        s += " (%s)" % license_url
    return s + ". Source: " + source_url


def candidate(**kw):
    base = {"source": None, "seed": None, "source_id": None, "title": None, "artist": None, "genre": None,
            "duration": None, "seconds": None, "license": None, "license_url": None, "credits": "",
            "audio": None, "audio_sha256": None, "cover": None, "cover_sha256": None, "source_url": None,
            "attribution": None, "needs_mirror": False, "low_bitrate": False, "kbps": None, "notes": []}
    base.update(kw)
    return base


# ---------------------------------------------------------------- archive.org

def archive_seed(seed, max_items, stats):
    lic = ('(licenseurl:http*creativecommons.org\\/licenses\\/by\\/* OR '
           'licenseurl:http*creativecommons.org\\/licenses\\/by-sa\\/* OR '
           'licenseurl:http*creativecommons.org\\/publicdomain\\/zero\\/*)')
    excl = "-collection:(audio_bookspoetry OR librivoxaudio OR oldtimeradio OR radioprograms OR podcasts OR non_quality_audio)"
    if seed["kind"] == "creator":
        q = 'creator:"%s" AND mediatype:audio AND %s AND %s' % (seed["id"], lic, excl)
    else:
        q = 'collection:"%s" AND mediatype:audio AND %s AND %s' % (seed["id"], lic, excl)
    params = [("q", q), ("fl[]", "identifier"), ("fl[]", "title"), ("fl[]", "licenseurl"),
              ("fl[]", "downloads"), ("sort[]", "downloads desc"), ("rows", str(max_items)), ("output", "json")]
    url = "https://archive.org/advancedsearch.php?" + urllib.parse.urlencode(params)
    docs = http_json(url)["response"]["docs"]
    stats["items"] += len(docs)
    out = []
    max_tracks = seed.get("max_tracks", 40)
    for d in docs:
        if len(out) >= max_tracks:
            break
        ident = d["identifier"]
        try:
            meta = http_json("https://archive.org/metadata/" + urllib.parse.quote(ident))
        except Exception as e:  # noqa: BLE001
            stats["errors"].append("%s: %s" % (ident, e))
            continue
        out.extend(archive_item(seed, ident, meta, stats))
    return out[:max_tracks]


def archive_item(seed, ident, meta, stats):
    m = meta.get("metadata", {})
    spdx, why = spdx_license(m.get("licenseurl"))
    if not spdx:
        stats["rejected"][why] = stats["rejected"].get(why, 0) + 1
        return []
    item_artist = first(m.get("creator")) or seed["id"]
    files = meta.get("files", [])
    names = {f.get("name") for f in files}
    cover = None
    for f in files:
        fmt = (f.get("format") or "").lower()
        if fmt in ("jpeg", "png", "jpeg thumb") or fmt.endswith("jpeg") or fmt == "png":
            if f.get("name", "").startswith("__ia_thumb"):
                continue
            cover = "https://archive.org/download/%s/%s" % (ident, urllib.parse.quote(f["name"]))
            break
    if not cover and "__ia_thumb.jpg" in names:
        cover = "https://archive.org/services/img/" + ident
    source_url = "https://archive.org/details/" + ident
    out = []
    for f in files:
        fmt = (f.get("format") or "")
        if "MP3" not in fmt:
            continue
        name = f["name"]
        # Prefer original MP3s; take a derivative MP3 only when the original is FLAC/OGG/WAV.
        if f.get("source") == "derivative":
            orig = f.get("original")
            if orig and orig.lower().endswith(".mp3"):
                continue
        sec = parse_len(f.get("length"))
        size = int(f.get("size") or 0)
        kbps = int(size * 8 / sec / 1000) if sec and size else None
        if sec is None or not (MIN_SEC <= sec <= MAX_SEC):
            stats["rejected"]["duration"] = stats["rejected"].get("duration", 0) + 1
            continue
        if kbps is not None and kbps < MIN_KBPS:
            stats["rejected"]["bitrate<%d" % MIN_KBPS] = stats["rejected"].get("bitrate<%d" % MIN_KBPS, 0) + 1
            continue
        title = clean_title(f.get("title") or os.path.splitext(name)[0])
        artist = (first(f.get("creator")) or first(f.get("artist")) or item_artist).strip()
        notes = []
        if not cover:
            notes.append("no artwork: realm SVG cover")
        out.append(candidate(
            source="archive", seed=seed["id"], source_id="%s/%s" % (ident, name), title=title, artist=artist,
            genre=seed["genre"], duration=clock(sec), seconds=round(sec, 1), license=spdx,
            license_url=m.get("licenseurl"), audio="https://archive.org/download/%s/%s" % (ident, urllib.parse.quote(name)),
            cover=cover, source_url=source_url,
            attribution=attribution(title, artist, spdx, m.get("licenseurl"), source_url),
            kbps=kbps, low_bitrate=bool(kbps and kbps < WARN_KBPS), notes=notes,
            archive_md5=f.get("md5"), archive_sha1=f.get("sha1")))
    return out


TITLE_NOISE = re.compile(r"\s*(\((cc[- ]?by[^)]*|cc0|creative commons[^)]*)\)|\[\d{5,}\])\s*", re.I)


def clean_title(t):
    """Drop uploader noise such as '(CC-BY)' or '[41199233]' from titles."""
    return re.sub(r"\s{2,}", " ", TITLE_NOISE.sub(" ", t)).strip(" -_")


def first(v):
    if isinstance(v, list):
        return v[0] if v else None
    return v


# ---------------------------------------------------------------- ccMixter

def ccmixter_seed(seed, max_items, stats):
    out, offset = [], 0
    while len(out) < max_items:
        limit = min(50, max_items - len(out))
        url = "https://ccmixter.org/api/query?f=json&%s&limit=%d&offset=%d" % (seed["id"], limit, offset)
        rows = http_json(url)
        if not rows:
            break
        offset += len(rows)
        stats["items"] += len(rows)
        for r in rows:
            c = ccmixter_row(seed, r, stats)
            if c:
                out.append(c)
        if len(rows) < limit:
            break
    return out[:max_items]


def ccmixter_row(seed, r, stats):
    spdx, why = spdx_license(r.get("license_url"))
    if not spdx:
        stats["rejected"][why] = stats["rejected"].get(why, 0) + 1
        return None
    mp3 = next((f for f in r.get("files", []) if (f.get("file_format_info") or {}).get("mime_type") == "audio/mpeg"), None)
    if not mp3:
        stats["rejected"]["no mp3"] = stats["rejected"].get("no mp3", 0) + 1
        return None
    info = mp3.get("file_format_info") or {}
    sec = parse_len(info.get("ps"))
    if sec is None or not (MIN_SEC <= sec <= MAX_SEC):
        stats["rejected"]["duration"] = stats["rejected"].get("duration", 0) + 1
        return None
    size = int(mp3.get("file_rawsize") or 0)
    kbps = int(size * 8 / sec / 1000) if size else None
    if kbps is not None and kbps < MIN_KBPS:
        stats["rejected"]["bitrate<%d" % MIN_KBPS] = stats["rejected"].get("bitrate<%d" % MIN_KBPS, 0) + 1
        return None
    title = r.get("upload_name", "").strip()
    artist = (r.get("user_real_name") or r.get("user_name") or "").strip()
    extra = r.get("upload_extra") or {}
    credits = ("feat. " + extra["featuring"]) if extra.get("featuring") else ""
    source_url = r.get("file_page_url")
    return candidate(
        source="ccmixter", seed=seed["id"], source_id=str(r.get("upload_id")), title=title, artist=artist,
        genre=seed["genre"], duration=clock(sec), seconds=round(sec, 1), license=spdx, license_url=r.get("license_url"),
        credits=credits, audio=mp3.get("download_url"), cover=None, source_url=source_url,
        attribution=attribution(title, artist, spdx, r.get("license_url"), source_url),
        needs_mirror=True, kbps=kbps, low_bitrate=bool(kbps and kbps < WARN_KBPS),
        notes=["ccMixter blocks hotlinking: mirror to IPFS/CDN before import", "no artwork: realm SVG cover"],
        ccmixter_sha1_b32=(mp3.get("file_extra") or {}).get("sha1"))


# ---------------------------------------------------------------- Audius

def audius_genre(g, default):
    g = (g or "").lower()
    for key, gid in AUDIUS_GENRES:
        if key in g:
            return gid
    return default


EDIT_RE = re.compile(r"\b(edit|remix|bootleg|flip|rework|mashup|cover|vip mix|stem drop|live set|mix vol)\b", re.I)


def audius_seed(seed, max_items, stats):
    user = http_json("%s/users/handle/%s?app_name=%s" % (AUDIUS, urllib.parse.quote(seed["id"]), APP))["data"]
    url = "%s/users/%s/tracks?app_name=%s&limit=%d&sort=plays" % (AUDIUS, user["id"], APP, min(100, max_items * 3))
    rows = http_json(url)["data"]
    stats["items"] += len(rows)
    out = []
    for t in rows:
        why = None
        if t.get("is_stream_gated") or not t.get("is_streamable", True) or t.get("is_delete") or t.get("is_unlisted"):
            why = "gated/unavailable"
        elif (t.get("remix_of") or {}).get("tracks") or t.get("cover_original_song_title") or t.get("stem_of"):
            why = "remix/cover/stem"
        elif EDIT_RE.search(t.get("title", "")):
            why = "title looks like an edit/remix/set"
        elif not (MIN_SEC <= (t.get("duration") or 0) <= MAX_SEC):
            why = "duration"
        elif not t.get("artwork"):
            why = "no artwork"
        if why:
            stats["rejected"][why] = stats["rejected"].get(why, 0) + 1
            continue
        sec = t["duration"]
        title = t["title"].strip()
        artist = user.get("name") or seed["id"]
        art = t["artwork"]
        cover = art.get("1000x1000") or art.get("480x480")
        source_url = "https://audius.co" + (t.get("permalink") or "/%s" % seed["id"])
        copyright_line = (t.get("copyright_line") or {}).get("text") if isinstance(t.get("copyright_line"), dict) else None
        attrib = '"%s" by %s © %s. Streamed under the Audius Open Music License. %s' % (
            title, artist, copyright_line or artist, source_url)
        out.append(candidate(
            source="audius", seed=seed["id"], source_id=t["id"], title=title, artist=artist,
            genre=audius_genre(t.get("genre"), seed["genre"]), duration=clock(sec), seconds=sec,
            license="Audius-OML", license_url="https://audius.org/open-music-license.pdf",
            audio="audius:" + t["id"], cover=cover, source_url=source_url, attribution=attrib,
            notes=["Audius genre: %s" % t.get("genre"), "API terms: session cache only, never mirror"],
            audius_user_id=user["id"], audius_wallets={k: user.get(k) for k in ("erc_wallet", "spl_wallet")}))
        if len(out) >= max_items:
            break
    return out


# ---------------------------------------------------------------- commands

def cmd_fetch(a):
    seeds = load(a.seeds, {"seeds": []})["seeds"]
    only = set(a.only.split(",")) if a.only else None
    cands = load(os.path.join(HERE, "candidates.json"), [])
    known = {(c["source"], c["source_id"]) for c in cands}
    report = []
    for s in seeds:
        if only and s["source"] not in only:
            continue
        if a.seed and s["id"] != a.seed:
            continue
        if s.get("status") == "paused" or (s.get("status") == "to_review" and not a.include_review and not a.seed):
            continue
        n = min(a.max_items or s.get("max_items", 50), s.get("max_items", 50))
        stats = {"items": 0, "rejected": {}, "errors": []}
        fn = {"archive": archive_seed, "ccmixter": ccmixter_seed, "audius": audius_seed}[s["source"]]
        try:
            got = fn(s, n, stats)
        except Exception as e:  # noqa: BLE001
            stats["errors"].append(str(e))
            got = []
        added = 0
        for c in got:
            k = (c["source"], c["source_id"])
            if k in known:
                continue
            known.add(k)
            cands.append(c)
            added += 1
        report.append((s["source"], s["id"], stats["items"], added, stats["rejected"], stats["errors"][:3]))
        print("%-9s %-24s items=%-4d added=%-4d rejected=%s%s" % (
            s["source"], s["id"][:24], stats["items"], added, stats["rejected"],
            ("  errors=%s" % stats["errors"][:3]) if stats["errors"] else ""))
        save(os.path.join(HERE, "candidates.json"), cands)
    print("candidates.json: %d tracks" % len(cands))


def cmd_hash(a):
    cands = load(os.path.join(HERE, "candidates.json"), [])
    cache = load(os.path.join(HERE, "hashes.json"), {})
    ff = shutil.which("ffmpeg")
    done = 0
    for c in cands:
        if c["source"] == "audius" or c.get("audio_sha256"):
            continue
        if c["audio"] in cache:
            c.update(cache[c["audio"]])
            continue
        if done >= a.max:
            break
        headers = {"User-Agent": UA}
        if c["source"] == "ccmixter":
            headers["Referer"] = c["source_url"]  # server-side mirror fetch; hotlinking from the app stays blocked
        req = urllib.request.Request(c["audio"], headers=headers)
        h = hashlib.sha256()
        size = 0
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    h.update(chunk)
                    size += len(chunk)
        except Exception as e:  # noqa: BLE001
            print("hash failed %s: %s" % (c["audio"], e))
            continue
        res = {"audio_sha256": h.hexdigest(), "bytes": size}
        if ff:
            res["lufs"] = lufs(ff, c["audio"], headers)
        cache[c["audio"]] = res
        c.update(res)
        done += 1
        print("%s  %s  %d bytes%s" % (res["audio_sha256"][:16], c["title"][:40], size,
                                       ("  %s LUFS" % res.get("lufs")) if ff else ""))
    save(os.path.join(HERE, "hashes.json"), cache)
    save(os.path.join(HERE, "candidates.json"), cands)
    if not ff:
        print("ffmpeg not found: LUFS skipped (brew install ffmpeg to enable)")


def lufs(ff, url, headers):
    hdr = "".join("%s: %s\r\n" % kv for kv in headers.items())
    try:
        p = subprocess.run([ff, "-hide_banner", "-nostats", "-headers", hdr, "-i", url, "-af", "ebur128", "-f", "null", "-"],
                           capture_output=True, text=True, timeout=300)
        m = re.findall(r"I:\s+(-?[0-9.]+) LUFS", p.stderr)
        return float(m[-1]) if m else None
    except Exception:  # noqa: BLE001
        return None


def cmd_batch(a):
    approved = load(a.approved, None)
    if approved is None:
        sys.exit("missing %s (export it from review.html)" % a.approved)
    artists, tracks, blocked = {}, [], []
    for c in approved:
        if c.get("needs_mirror") and not c.get("mirror_audio"):
            blocked.append(c)
            continue
        key = "%s:%s" % (c["source"], c["artist"].lower())
        if key not in artists:
            artists[key] = {"key": key, "name": c["artist"], "source": c["source"],
                            "source_url": ("https://audius.co/" + c["seed"]) if c["source"] == "audius" else c["source_url"],
                            "kind": "audius" if c["source"] == "audius" else "curated"}
        if c["source"] != "audius" and not c.get("audio_sha256"):
            blocked.append(c)
            continue
        tracks.append({
            "artist_key": key, "title": c["title"], "genre": c["genre"], "duration": c["duration"],
            "license": c["license"], "credits": c.get("credits", ""), "audio": c.get("mirror_audio") or c["audio"],
            "audio_sha256": c.get("audio_sha256") or "", "cover": c.get("cover") or "", "cover_sha256": c.get("cover_sha256") or "",
            "source_url": c["source_url"], "attribution": c["attribution"]})
    counts = {g: 0 for g in GENRES}
    for t in tracks:
        counts[t["genre"]] = counts.get(t["genre"], 0) + 1
    out = {"generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "artists": list(artists.values()),
           "tracks": tracks, "genre_counts": {GENRES[g]: n for g, n in counts.items()}}
    save(os.path.join(HERE, "import_batch.json"), out)
    print("import_batch.json: %d artists, %d tracks (%d blocked: missing mirror or sha256)" % (
        len(artists), len(tracks), len(blocked)))
    print("%-24s %5s / %d" % ("genre", "count", TARGET_PER_GENRE))
    for g in GENRES:
        n = counts.get(g, 0)
        bar = "#" * min(40, n * 40 // TARGET_PER_GENRE)
        print("%-24s %5d  %s%s" % (GENRES[g], n, bar, "  (short)" if n < TARGET_PER_GENRE else ""))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch")
    f.add_argument("--seeds", default=os.path.join(HERE, "seeds.json"))
    f.add_argument("--only", help="archive,ccmixter,audius")
    f.add_argument("--seed", help="fetch a single seed id (status ignored)")
    f.add_argument("--max-items", type=int, help="cap per seed (items for archive, tracks otherwise)")
    f.add_argument("--include-review", action="store_true", help="also fetch seeds with status to_review")
    h = sub.add_parser("hash")
    h.add_argument("--max", type=int, default=20)
    b = sub.add_parser("batch")
    b.add_argument("--approved", default=os.path.join(HERE, "approved.json"))
    a = p.parse_args()
    {"fetch": cmd_fetch, "hash": cmd_hash, "batch": cmd_batch}[a.cmd](a)


if __name__ == "__main__":
    main()
