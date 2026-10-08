#!/usr/bin/env python3
"""GnoRadio launch-catalog curation pipeline (standard library only).

  curate.py fetch  [--seeds seeds.json] [--only SRC[,SRC]] [--seed ID] [--max-items N] [--include-review]
  curate.py hash   [--max N]                 sha256 (+ LUFS if ffmpeg) for non-Audius candidates
  curate.py batch  [--approved approved.json] [--dry-run]
                                             build import_batch.json for radio.ImportTrack;
                                             every row is checked against the realm's rules first
  curate.py devseed [--per N] [--batch N]    local devnet only: Audius trending tracks per genre
                                             -> gno/r/gnoradio/devseed/v0/data.gno (gitignored)

Rule: every track comes from a whitelisted seed (seeds.json). Never open-ended search.
"""
import argparse
import concurrent.futures
import hashlib
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = "GnoRadioCurate/0.1 (+https://gno.land; catalog curation, whitelist only)"
APP = "GnoRadio"
AUDIUS = "https://api.audius.co/v1"

GENRES = {1: "Electronica", 2: "Synthwave", 3: "Ambient", 4: "Techno", 5: "House", 6: "Drum & Bass",
          7: "Dubstep & Trap", 8: "Lo-fi Beats", 9: "Hip-hop & Rap", 10: "R&B & Soul", 11: "Rock & Indie",
          12: "Metal & Punk", 13: "Pop", 14: "Jazz & Blues", 15: "Folk & Acoustic", 16: "Cinematic & Classical",
          17: "World", 18: "Latin", 19: "Reggae & Dub", 20: "Funk & Disco"}
TARGET_PER_GENRE = 80

MIN_SEC, MAX_SEC = 90, 600
LONG_GENRES = {3, 16}   # Ambient and Cinematic & Classical may run to 15:00
LONG_MAX_SEC = 900
MIN_KBPS = 160      # quality gate: estimated size*8/length
WARN_KBPS = 192     # below this the candidate is flagged low_bitrate for the reviewer
AUDIO_FORMATS = ("MP3", "OGG VORBIS")  # archive.org format names accepted (case-insensitive)
LIC_VERSIONS = {"1.0", "2.0", "2.5", "3.0", "4.0"}  # unported only (no jurisdiction ports); in sync with CURATED_LIC_RE

# Audius genre (or, for a broad electronic genre, tag) -> GnoRadio genre id
# (first match wins; checked on lowercase, so "trap" precedes "rap" and "dubstep" precedes "dub").
AUDIUS_GENRES = [
    ("synthwave", 2), ("retrowave", 2), ("outrun", 2), ("vaporwave", 2), ("ambient", 3), ("techno", 4),
    ("house", 5), ("garage", 5), ("drum & bass", 6), ("drum and bass", 6), ("dnb", 6), ("jungle", 6),
    ("dubstep", 7), ("future bass", 7), ("hardstyle", 7), ("trap", 7), ("lo-fi", 8), ("lofi", 8),
    ("downtempo", 8), ("chill", 8), ("hip-hop", 9), ("hip hop", 9), ("rap", 9), ("r&b", 10), ("soul", 10),
    ("metal", 12), ("punk", 12), ("rock", 11), ("alternative", 11), ("indie", 11), ("pop", 13), ("jazz", 14),
    ("blues", 14), ("folk", 15), ("acoustic", 15), ("country", 15), ("singer-songwriter", 15),
    ("classical", 16), ("soundtrack", 16), ("cinematic", 16), ("moombahton", 18), ("reggaeton", 18),
    ("latin", 18), ("dancehall", 19), ("reggae", 19), ("dub", 19), ("funk", 20), ("disco", 20),
    ("world", 17), ("afro", 17), ("electro", 1), ("glitch hop", 1), ("experimental", 1), ("trance", 1),
    ("edm", 1),
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


def unknown_size_ok(fmt):
    """Size missing so kbps is unknown: trust VBR MP3 or a stated 192+ kbps format; else reject as 'unknown size'."""
    m = re.search(r"(\d+)\s*kbps", fmt or "", re.I)
    return "VBR" in (fmt or "").upper() or bool(m and int(m.group(1)) >= 192)


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
    """Map a Creative Commons URL to (SPDX id, port) or (None, reason). Only CC0, BY, BY-SA, BY-NC, BY-NC-SA pass (never ND)."""
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
    elif code in ("by-sa", "by-nc", "by-nc-sa"):
        spdx = "CC-" + code.upper() + "-" + ver
    else:
        return None, "excluded license CC " + code.upper()
    if ver not in LIC_VERSIONS:
        return None, "licence version " + ver
    if port:
        return None, "jurisdiction port " + port
    return spdx, None


# ---------------------------------------------------------------- realm rules
# Mirrors gno/r/gnoradio/catalog/v1/validate.gno so a batch never panics on chain.

TEXT_PUNCT = set(" .,'-!?:/&")
NAME_PUNCT = set(" .'-&")
URL_CHARS = set("-._~:/?#=&%+@")
ALLOWED_HOSTS = {"archive.org", "upload.wikimedia.org"}  # catalog init(); AllowHost adds more
MAX_TITLE, MAX_CREDITS, MAX_ATTRIBUTION, MAX_NAME, MAX_BIO = 64, 160, 160, 40, 280
CURATED_LIC_RE = re.compile(r"^(CC0-1\.0|CC-BY(-NC)?(-SA)?-(1\.0|2\.0|2\.5|3\.0|4\.0)(-[A-Z0-9]{2})?)$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
CLOCK_RE = re.compile(r"^(\d{1,3}):([0-5]\d)$")


def text_ok(s, lo, hi):
    """text.Valid: letters (any script), digits, spaces and . , ' - ! ? : / & only;
    no fullwidth or mathematical letters, no blank Hangul fillers."""
    for ch in s:
        o = ord(ch)
        if 0xFF01 <= o <= 0xFF5E or 0x1D400 <= o <= 0x1D7FF or o in (0x115F, 0x1160, 0x3164, 0xFFA0):
            return False
        if not (ch.isalpha() or unicodedata.category(ch) == "Nd" or ch in TEXT_PUNCT):
            return False
    return lo <= len(s) <= hi


def name_ok(s):
    """validName: ASCII letters/digits, Latin-1 accents, single spaces and . ' - &."""
    if s != s.strip() or "  " in s:
        return False
    for ch in s:
        o = ord(ch)
        if ch.isascii() and ch.isalnum():
            continue
        if 0xC0 <= o <= 0xFF and o not in (0xD7, 0xF7):
            continue
        if ch in NAME_PUNCT:
            continue
        return False
    return 2 <= len(s) <= MAX_NAME


def https_ok(u):
    return bool(u) and u.startswith("https://") and 10 < len(u) <= 300 and all(
        (c.isascii() and c.isalnum()) or c in URL_CHARS for c in u)


def host_of(u):
    return u[len("https://"):].split("/", 1)[0].lower()


def media_problem(field, uri, sha, audio):
    """mustMedia: returns None when the realm would accept uri/sha, else why not."""
    if sha and not SHA_RE.match(sha):
        return field + " sha256 must be 64 hex characters"
    if uri.startswith("ipfs://"):
        cid = uri[7:]
        return None if 46 <= len(cid) <= 100 and cid.isascii() and cid.isalnum() else field + " ipfs:// needs a CID"
    if uri.startswith("ar://"):
        return None if len(uri) - 5 == 43 else field + " ar:// needs a 43-character id"
    if uri.startswith("audius:"):
        tid = uri[7:]
        return None if audio and tid.isascii() and tid.isalnum() and 1 <= len(tid) <= 24 else field + " audius: is audio only"
    if uri.startswith("https://"):
        if not https_ok(uri) or host_of(uri) not in ALLOWED_HOSTS:
            return field + " host not allowed: " + host_of(uri)
        return None if sha else field + " over https needs its sha256"
    return field + " must be ipfs://, ar://, audius: or an allowed https link"


def clean_text(s, hi):
    """Rewrite s into validText's alphabet: brackets become ' - ', quotes and
    symbols go, whitespace collapses, and it is cut at a word under hi runes."""
    s = unicodedata.normalize("NFC", s or "")
    s = s.replace("\u2019", "'").replace("\u2018", "'").replace("\u2013", "-").replace("\u2014", "-")
    s = s.replace("_", " ").replace(";", ",")
    s = re.sub(r"\s*[\(\[\{]\s*", " - ", s)
    s = re.sub(r"\s*[\)\]\}]\s*", " ", s)
    s = "".join(ch if (ch.isalpha() or unicodedata.category(ch) == "Nd" or ch in TEXT_PUNCT) else " " for ch in s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"(\s*-\s*){2,}", " - ", s).strip(" -,:")
    if len(s) > hi:
        s = s[:hi].rsplit(" ", 1)[0].rstrip(" -,:")
    return s


def license_label(spdx):
    if spdx == "CC0-1.0":
        return "CC0 1.0"
    if spdx == "Audius-OML":
        return "Audius Open Music License"
    if spdx and spdx.startswith("CC-"):
        parts = spdx[3:].split("-")
        ver = next((i for i, p in enumerate(parts) if "." in p), None)
        if ver is not None:
            return "CC " + "-".join(parts[:ver]) + " " + " ".join(parts[ver:])
    return spdx or ""


def attribution(title, artist, spdx, via=""):
    """'Title by Artist, CC BY 4.0, via archive.org': the realm keeps the source
    link in sourceURL, so it is not repeated here (and URLs are not validText)."""
    s = "%s by %s, %s" % (title, artist, license_label(spdx))
    if via:
        s += ", via " + via
    return clean_text(s, MAX_ATTRIBUTION)


def track_problems(t):
    """Every reason radio.ImportTrack would panic on this batch row."""
    out = []
    if not text_ok(t["title"], 1, MAX_TITLE):
        out.append("title")
    if not text_ok(t.get("credits", ""), 0, MAX_CREDITS):
        out.append("credits")
    if not text_ok(t["attribution"], 2, MAX_ATTRIBUTION):
        out.append("attribution")
    if not (1 <= int(t["genre"]) <= len(GENRES)):
        out.append("genre")
    m = CLOCK_RE.match(t["duration"] or "")
    if not m or not (10 <= int(m.group(1)) * 60 + int(m.group(2)) <= 1200):
        out.append("duration")
    audius = t["audio"].startswith("audius:")
    if not audius and not CURATED_LIC_RE.match(t["license"] or ""):
        out.append("license " + str(t["license"]))
    if not https_ok(t["source_url"]):
        out.append("source_url")
    p = media_problem("audio", t["audio"], t["audio_sha256"], True)
    if p:
        out.append(p)
    if t["cover"]:
        p = media_problem("cover", t["cover"], t["cover_sha256"], False)
        if p:
            out.append(p)
    return out


_LATIN1 = ["a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i",
           "d", "n", "o", "o", "o", "o", "o", "", "o", "u", "u", "u", "u", "y", "th", "ss"] * 2


def skeleton(name):
    """Mirror of catalog validate.gno skeleton(): the key a name is reserved under on chain."""
    out = []
    for ch in name:
        if ch in " .'-&\u3000":
            continue
        o = ord(ch)
        if 0xFF21 <= o <= 0xFF3A or 0xFF41 <= o <= 0xFF5A:
            ch = chr(ord("a") + (o - 0xFF21) % 32)
        elif 0xFF10 <= o <= 0xFF19:
            ch = chr(ord("0") + o - 0xFF10)
        ch = ch.lower()
        if 0xC0 <= ord(ch) <= 0xFF and _LATIN1[ord(ch) - 0xC0]:
            ch = _LATIN1[ord(ch) - 0xC0]
        out.append({"i": "l", "1": "l", "|": "l", "0": "o"}.get(ch, ch))
    return "".join(out).replace("rn", "m")


def artist_problems(a):
    out = []
    if not name_ok(a["name"]):
        out.append("artist name " + repr(a["name"]))
    if a["source_url"] and not https_ok(a["source_url"]):
        out.append("artist source_url")
    return out


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
           'licenseurl:http*creativecommons.org\\/licenses\\/by-nc\\/* OR '
           'licenseurl:http*creativecommons.org\\/licenses\\/by-nc-sa\\/* OR '
           'licenseurl:http*creativecommons.org\\/publicdomain\\/zero\\/*)')
    excl = "-collection:(audio_bookspoetry OR librivoxaudio OR oldtimeradio OR radioprograms OR podcasts OR non_quality_audio)"
    if seed["kind"] == "items":
        out = []
        for ident in seed["ids"]:
            try:
                meta = http_json("https://archive.org/metadata/" + urllib.parse.quote(ident))
                if not meta.get("metadata"):
                    raise ValueError("item not found")
            except Exception as e:  # noqa: BLE001
                stats["errors"].append("%s: %s" % (ident, e))
                continue
            stats["items"] += 1
            out.extend(archive_item(seed, ident, meta, stats))
        return out
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


COVER_NAME = re.compile(r"(^|[^a-z])(cover|folder|front|artwork|album)([^a-z]|$)", re.I)
BACK_NAME = re.compile(r"back|inlay|booklet|tray|disc|cd\d", re.I)
IMG_EXT = (".jpg", ".jpeg", ".png")


def original_cover(ident, files):
    """Cover URL from the item's ORIGINAL images only (never archive.org's derived waveform PNGs or thumbs).
    An image named like cover/folder/front wins, else the only original image. Per-track art (same stem as an
    audio file, or '01 Song.jpg') is not an album cover."""
    stems = set()
    for f in files:
        fmt = (f.get("format") or "").upper()
        if any(k in fmt for k in ("MP3", "OGG VORBIS", "FLAC", "WAVE", "AIFF", "APPLE LOSSLESS")):
            stems.add(os.path.splitext(first(f.get("original")) or f["name"])[0])
            stems.add(os.path.splitext(f["name"])[0])
    imgs = [f["name"] for f in files if f.get("source") == "original" and f["name"].lower().endswith(IMG_EXT)
            and "/" not in f["name"] and not f["name"].startswith("__ia_thumb")]
    named = [n for n in imgs if COVER_NAME.search(os.path.splitext(n)[0]) and not BACK_NAME.search(n)]
    album = [n for n in imgs if not BACK_NAME.search(n) and os.path.splitext(n)[0] not in stems and not re.match(r"\d{1,3}[ ._-]", n)]
    pick = named[0] if named else album[0] if len(album) == 1 else None
    return "https://archive.org/download/%s/%s" % (ident, urllib.parse.quote(pick)) if pick else None


def archive_item(seed, ident, meta, stats):
    m = meta.get("metadata", {})
    spdx, why = spdx_license(m.get("licenseurl"))
    if not spdx:
        stats["rejected"][why] = stats["rejected"].get(why, 0) + 1
        stats.setdefault("rejected_items", []).append((ident, why))
        return []
    if seed.get("only_licenses") and spdx not in seed["only_licenses"]:
        stats["rejected"]["licence not wanted"] = stats["rejected"].get("licence not wanted", 0) + 1
        stats.setdefault("rejected_items", []).append((ident, "licence " + spdx + " not in seed's only_licenses"))
        return []
    xr = seed.get("exclude_title_re")
    if xr and re.search(xr, str(m.get("title", "")), re.I):
        stats.setdefault("rejected_items", []).append((ident, "excluded title: " + str(m.get("title"))))
        return []
    item_artist = first(m.get("creator")) or seed.get("artist") or seed["id"]
    files = meta.get("files", [])
    cover = original_cover(ident, files)
    source_url = "https://archive.org/details/" + ident
    out = []
    genre = seed.get("genre_overrides", {}).get(ident, seed["genre"])
    max_sec = LONG_MAX_SEC if genre in LONG_GENRES else MAX_SEC
    # One file per track: an original mp3/ogg wins; else a derivative mp3, then a derivative ogg.
    best = {}
    for f in files:
        fmt = (f.get("format") or "").upper()
        fmt = "MP3" if "MP3" in fmt else "OGG VORBIS" if "OGG VORBIS" in fmt else None  # "VBR MP3", "128Kbps MP3"
        if not fmt:
            continue
        deriv = f.get("source") == "derivative"
        stem = os.path.splitext(f.get("original") or f["name"])[0] if deriv else os.path.splitext(f["name"])[0]
        rank = (1 if deriv else 0, 0 if fmt == "MP3" else 1)
        if stem not in best or rank < best[stem][0]:
            best[stem] = (rank, f)
    for _, f in sorted(best.values(), key=lambda x: x[1]["name"]):
        name = f["name"]
        sec = parse_len(f.get("length"))
        size = int(f.get("size") or 0)
        kbps = int(size * 8 / sec / 1000) if sec and size else None
        if sec is None or not (MIN_SEC <= sec <= max_sec):
            stats["rejected"]["duration"] = stats["rejected"].get("duration", 0) + 1
            continue
        if kbps is None and not unknown_size_ok(f.get("format")):
            stats["rejected"]["unknown size"] = stats["rejected"].get("unknown size", 0) + 1
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
            genre=genre, duration=clock(sec), seconds=round(sec, 1), license=spdx,
            license_url=m.get("licenseurl"), audio="https://archive.org/download/%s/%s" % (ident, urllib.parse.quote(name)),
            cover=cover, source_url=source_url,
            attribution=attribution(title, artist, spdx, "archive.org"),
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
    max_sec = LONG_MAX_SEC if seed["genre"] in LONG_GENRES else MAX_SEC
    if sec is None or not (MIN_SEC <= sec <= max_sec):
        stats["rejected"]["duration"] = stats["rejected"].get("duration", 0) + 1
        return None
    size = int(mp3.get("file_rawsize") or 0)
    kbps = int(size * 8 / sec / 1000) if size else None
    if kbps is None:
        stats["rejected"]["unknown size"] = stats["rejected"].get("unknown size", 0) + 1
        return None
    if kbps < MIN_KBPS:
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
        attribution=attribution(title, artist, spdx, "ccMixter"),
        needs_mirror=True, kbps=kbps, low_bitrate=bool(kbps and kbps < WARN_KBPS),
        notes=["ccMixter blocks hotlinking: mirror to IPFS/CDN before import", "no artwork: realm SVG cover"],
        ccmixter_sha1_b32=(mp3.get("file_extra") or {}).get("sha1"))


# ---------------------------------------------------------------- Audius

def audius_genre(g, default, tags=""):
    """Map an Audius genre to a GnoRadio id; a broad electronic genre is refined by the track's tags."""
    gid = next((i for k, i in AUDIUS_GENRES if k in (g or "").lower()), default)
    if gid == 1 and tags:
        gid = next((i for k, i in AUDIUS_GENRES if k in tags.lower()), 1)
    return gid


OML_RE = re.compile(r"\bopen music licen[sc]e\b|^oml$", re.I)
EDIT_RE = re.compile(r"\b(edit|remix|bootleg|flip|rework|mashup|cover|vip mix|stem drop|live set|mix vol)\b", re.I)


def audius_problem(t, max_sec=MAX_SEC):
    """Why an Audius track is not a streamable original with artwork (None when it is)."""
    if t.get("is_stream_gated") or not t.get("is_streamable", True) or t.get("is_delete") or t.get("is_unlisted"):
        return "gated/unavailable"
    if (t.get("remix_of") or {}).get("tracks") or t.get("cover_original_song_title") or t.get("stem_of"):
        return "remix/cover/stem"
    if EDIT_RE.search(t.get("title", "")):
        return "title looks like an edit/remix/set"
    if not (MIN_SEC <= (t.get("duration") or 0) <= max_sec):
        return "duration"
    if not t.get("artwork"):
        return "no artwork"
    # The artist's own license overrides the Open Music License: keep only tracks with none, or the OML itself.
    lic = (t.get("license") or "").strip()
    if lic and not OML_RE.search(lic):
        return "own license: " + lic
    return None


def audius_seed(seed, max_items, stats):
    user = http_json("%s/users/handle/%s?app_name=%s" % (AUDIUS, urllib.parse.quote(seed["id"]), APP))["data"]
    url = "%s/users/%s/tracks?app_name=%s&limit=%d&sort=plays" % (AUDIUS, user["id"], APP, min(100, max_items * 3))
    rows = http_json(url)["data"]
    stats["items"] += len(rows)
    out = []
    for t in rows:
        why = audius_problem(t, LONG_MAX_SEC if seed["genre"] in LONG_GENRES else MAX_SEC)
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
        attrib = attribution(title, artist, "Audius-OML", "Audius")
        if copyright_line:
            attrib = clean_text(attrib + ", copyright " + copyright_line, MAX_ATTRIBUTION)
        out.append(candidate(
            source="audius", seed=seed["id"], source_id=t["id"], title=title, artist=artist,
            genre=audius_genre(t.get("genre"), seed["genre"], t.get("tags") or ""), duration=clock(sec), seconds=sec,
            license="Audius-OML", license_url="https://openaudiofoundation.org/open-music-license.pdf",
            audio="audius:" + t["id"], cover=None, preview_cover=cover, source_url=source_url, attribution=attrib,
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
        for ident, why in stats.get("rejected_items", []):
            print("  rejected item %s: %s" % (ident, why))
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
        cov = c.get("cover")
        if cov and not c.get("cover_sha256") and cov.startswith("https://") and host_of(cov) in ALLOWED_HOSTS:
            if cov in cache:
                c["cover_sha256"] = cache[cov]["sha256"]
            elif done < a.max:
                digest = sha256_url(cov, {"User-Agent": UA})
                if digest:
                    cache[cov] = {"sha256": digest}
                    c["cover_sha256"] = digest
                    done += 1
        if c["source"] == "audius" or c.get("audio_sha256"):
            continue
        if c["audio"] in cache:
            c.update(cache[c["audio"]])
    todo = [c for c in cands if c["source"] != "audius" and not c.get("audio_sha256")][:a.max]

    def one(c):
        headers = {"User-Agent": UA}
        if c["source"] == "ccmixter":
            headers["Referer"] = c["source_url"]  # server-side mirror fetch; hotlinking from the app stays blocked
        got = digest_url(c["audio"], headers)
        if not got:
            return c, None
        res = {"audio_sha256": got[0], "bytes": got[1]}
        if ff and "lufs60" not in c:  # the loud step already measured most tracks: no second download
            res["lufs"] = lufs(ff, c["audio"], headers)
        return c, res

    # ponytail: 8 parallel downloads, a polite ceiling for archive.org; raise it only if they allow it.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for n, (c, res) in enumerate(pool.map(one, todo), 1):
            if res is None:
                continue
            cache[c["audio"]] = res
            c.update(res)
            print("%s  %s  %d bytes" % (res["audio_sha256"][:16], c["title"][:40], res["bytes"]))
            if n % 50 == 0:  # a crash loses at most 50 downloads
                save(os.path.join(HERE, "hashes.json"), cache)
    save(os.path.join(HERE, "hashes.json"), cache)
    save(os.path.join(HERE, "candidates.json"), cands)
    if not ff:
        print("ffmpeg not found: LUFS skipped (brew install ffmpeg to enable)")


def digest_url(url, headers):
    """(sha256 hex, bytes) of the file at url, None if it could not be read."""
    h = hashlib.sha256()
    size = 0
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120) as r:
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    return h.hexdigest(), size
                h.update(chunk)
                size += len(chunk)
    except Exception as e:  # noqa: BLE001
        print("hash failed %s: %s" % (url, e))
        return None


def sha256_url(url, headers):
    got = digest_url(url, headers)
    return got[0] if got else None


def lufs(ff, url, headers):
    hdr = "".join("%s: %s\r\n" % kv for kv in headers.items())
    try:
        p = subprocess.run([ff, "-hide_banner", "-nostats", "-headers", hdr, "-i", url, "-af", "ebur128", "-f", "null", "-"],
                           capture_output=True, text=True, timeout=300)
        m = re.findall(r"I:\s+(-?[0-9.]+) LUFS", p.stderr)
        return float(m[-1]) if m else None
    except Exception:  # noqa: BLE001
        return None


def loud_sample(ff, c):
    """ebur128 on the first 60 s: one HTTP range request, piped to ffmpeg. Returns (LUFS, true peak dBTP)."""
    kbps = c.get("kbps") or 320
    n = int(60 * kbps * 1000 / 8 * 1.15) + 65536
    req = urllib.request.Request(c["audio"], headers={"User-Agent": UA, "Range": "bytes=0-%d" % n})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read(n + 1)
        p = subprocess.run([ff, "-hide_banner", "-nostats", "-i", "pipe:0", "-t", "60", "-af", "ebur128=peak=true",
                            "-f", "null", "-"], input=data, capture_output=True, timeout=120)
        err = p.stderr.decode("utf-8", "replace")
        i = re.findall(r"I:\s+(-?[0-9.]+) LUFS", err)
        tp = re.findall(r"Peak:\s+(-?[0-9.]+) dBFS", err)
        return (float(i[-1]) if i else None), (float(tp[-1]) if tp else None)
    except Exception:  # noqa: BLE001
        return None, None


def cmd_loud(a):
    """Sampled loudness / clipping check. Flags only (notes), never drops: true peak >= -0.1 dBTP is clipping risk,
    integrated > -9 LUFS is crushed, < -30 LUFS is too quiet."""
    ff = shutil.which("ffmpeg")
    if not ff:
        sys.exit("ffmpeg not found")
    cands = load(os.path.join(HERE, "candidates.json"), [])
    todo = [c for c in cands if c["source"] == "archive" and "lufs60" not in c]
    def one(c):
        c["lufs60"], c["tp60"] = loud_sample(ff, c)
        flags = []
        if c["tp60"] is not None and c["tp60"] >= -0.1:
            flags.append("clipping risk")
        if c["lufs60"] is not None and c["lufs60"] > -9:
            flags.append("very loud")
        if c["lufs60"] is not None and c["lufs60"] < -30:
            flags.append("very quiet")
        c["loud_flags"] = flags
    with concurrent.futures.ThreadPoolExecutor(4) as ex:
        list(ex.map(one, todo))
    save(os.path.join(HERE, "candidates.json"), cands)
    done = [c for c in cands if c.get("lufs60") is not None]
    print("loudness: %d sampled, %d measured, %d flagged" % (len(todo), len(done), sum(1 for c in done if c["loud_flags"])))


def cmd_batch(a):
    approved = load(a.approved, None)
    if approved is None:
        sys.exit("missing %s (export it from review.html)" % a.approved)
    artists, tracks, blocked = {}, [], []
    skeletons = {}  # skeleton -> artist key, to catch on-chain name collisions in --dry-run
    for c in approved:
        if c.get("needs_mirror") and not c.get("mirror_audio"):
            blocked.append((c, ["needs a mirror"]))
            continue
        key = "%s:%s" % (c["source"], c["artist"].lower())
        if key not in artists:
            artists[key] = {"key": key, "name": c["artist"], "source": c["source"],
                            "source_url": ("https://audius.co/" + c["seed"]) if c["source"] == "audius" else c["source_url"],
                            "kind": "audius" if c["source"] == "audius" else "curated"}
        if c["source"] != "audius" and not c.get("audio_sha256"):
            blocked.append((c, ["missing audio sha256"]))
            continue
        title = clean_text(c["title"], MAX_TITLE)
        cover, cover_sha = c.get("cover") or "", c.get("cover_sha256") or ""
        if c["source"] == "audius" or (cover.startswith("https://") and not cover_sha):
            cover, cover_sha = "", ""  # Audius art is read live; unhashed art falls back to the realm SVG
        via = {"archive": "archive.org", "ccmixter": "ccMixter", "audius": "Audius"}.get(c["source"], "")
        row = {
            "artist_key": key, "title": title, "genre": c["genre"], "duration": c["duration"],
            "license": c["license"], "credits": clean_text(c.get("credits", ""), MAX_CREDITS),
            "audio": c.get("mirror_audio") or c["audio"], "audio_sha256": c.get("audio_sha256") or "",
            "cover": cover, "cover_sha256": cover_sha, "source_url": c["source_url"],
            "attribution": attribution(title, clean_text(c["artist"], 60), c["license"], via)}
        problems = track_problems(row) + artist_problems(artists[key])
        # Two different artists whose names fold to the same skeleton collide on chain.
        sk = skeleton(c["artist"])
        if skeletons.setdefault(sk, key) != key:
            problems.append("artist name collides with %r on chain" % skeletons[sk])
        if problems:
            blocked.append((c, problems))
            continue
        tracks.append(row)
    counts = {g: 0 for g in GENRES}
    for t in tracks:
        counts[t["genre"]] = counts.get(t["genre"], 0) + 1
    out = {"generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "artists": list(artists.values()),
           "tracks": tracks, "genre_counts": {GENRES[g]: n for g, n in counts.items()}}
    for c, why in blocked:
        print("blocked  %-40s %s" % (c["title"][:40], "; ".join(why)))
    used = {t["artist_key"] for t in tracks}
    out["artists"] = [x for x in out["artists"] if x["key"] in used]
    if a.dry_run:
        print("dry run: %d tracks would import, %d blocked (nothing written)" % (len(tracks), len(blocked)))
    else:
        save(os.path.join(HERE, "import_batch.json"), out)
        print("import_batch.json: %d artists, %d tracks (%d blocked)" % (len(out["artists"]), len(tracks), len(blocked)))
    print("%-24s %5s / %d" % ("genre", "count", TARGET_PER_GENRE))
    for g in GENRES:
        n = counts.get(g, 0)
        bar = "#" * min(40, n * 40 // TARGET_PER_GENRE)
        print("%-24s %5d  %s%s" % (GENRES[g], n, bar, "  (short)" if n < TARGET_PER_GENRE else ""))


# ---------------------------------------------------------------- devnet seed

# Audius genres whose trending lists fill the local devnet (dev only, never the launch catalog).
DEVSEED_GENRES = [
    "Electronic", "Electro", "Glitch Hop", "Experimental", "Trance", "Synthwave", "Vaporwave", "Ambient", "Techno",
    "House", "Deep House", "Tech House", "Progressive House", "Future House", "Tropical House", "Drum & Bass", "Jungle",
    "Dubstep", "Future Bass", "Trap", "Hardstyle", "Lo-Fi", "Downtempo", "Hip-Hop/Rap", "R&B/Soul", "Rock",
    "Alternative", "Metal", "Punk", "Pop", "Hyperpop", "Jazz", "Blues", "Folk", "Acoustic", "Country", "Soundtrack",
    "Classical", "World", "Latin", "Moombahton", "Reggaeton", "Reggae", "Dancehall", "Funk", "Disco",
]
DEVSEED_TAKEN = ("Scott Buckley", "ATTLAS", "Lea Kosmos", "Tryad")  # devseed.Base and the demo artists
DEVSEED_OUT = os.path.join(HERE, "..", "..", "gno", "r", "gnoradio", "devseed", "v0", "data.gno")
# Mirror of p/gnoradio/safe hate list, glued: a title or name holding one panics a whole batch.
HATE = ("nigg", "fagg", "kike", "chink", "gook", "wetback", "raghead", "towelhead", "tranny", "trannies",
        "zipperhead", "junglebunny", "porchmonkey", "untermensch", "holohoax", "heilhitler", "siegheil",
        "whitepower", "gasthejews", "killthejews", "killalljews")


def slur(s):
    """Stricter than safe.Slur: letters and leet digits glued, so any hit is refused."""
    f = "".join("oizeasgtbg"[int(c)] if c.isdigit() else c
                for c in unicodedata.normalize("NFKD", s.lower()) if c.isascii() and c.isalnum())
    sq = re.sub(r"(.)\1+", r"\1", f)
    return any(w in f or w in sq for w in HATE)


def audius_trending(genre):
    """Every track of an Audius genre's trending lists (all time, month, week) and underground list."""
    lists = [("trending", {"time": tm, "offset": off}) for tm in ("allTime", "month", "week") for off in (0, 100, 200)]
    lists += [("trending/underground", {"offset": off}) for off in range(0, 500, 100)]
    for path, q in lists:
        q.update(genre=genre, limit=100, app_name=APP)
        try:
            yield from http_json("%s/tracks/%s?%s" % (AUDIUS, path, urllib.parse.urlencode(q)), 0)["data"] or []
        except urllib.error.HTTPError:
            continue  # offset past the end of the list


def cmd_devseed(a):
    picked = {g: [] for g in GENRES}
    seen, titles, per = set(), set(), {}
    owner = {skeleton(n): "" for n in DEVSEED_TAKEN}  # skeleton -> Audius handle
    with concurrent.futures.ThreadPoolExecutor(6) as pool:  # Audius answers slowly; 6 lists in flight
        lists = list(pool.map(lambda ag: list(audius_trending(ag)), DEVSEED_GENRES))
    for ag, got in zip(DEVSEED_GENRES, lists):
        for t in got:
            g = audius_genre(t.get("genre"), None, t.get("tags") or "")
            if t["id"] in seen or not g or len(picked[g]) >= a.per or audius_problem(t):
                continue
            name, handle = (t["user"]["name"] or "").strip(), t["user"]["handle"]
            title, sk = clean_text(t["title"], MAX_TITLE), skeleton(name)
            if not (name_ok(name) and sk and text_ok(title, 1, MAX_TITLE) and https_ok("https://audius.co/" + handle)):
                continue
            if slur(name + " " + title) or owner.setdefault(sk, handle) != handle:
                continue
            if per.get(sk, 0) >= a.per_artist or (sk, title.lower()) in titles:
                continue
            slug = urllib.parse.quote(urllib.parse.unquote((t.get("permalink") or "").split("/", 2)[-1]), safe="-._~")
            if not https_ok("https://audius.co/%s/%s" % (handle, slug)):
                slug = ""
            seen.add(t["id"])
            titles.add((sk, title.lower()))
            per[sk] = per.get(sk, 0) + 1
            picked[g].append("|".join((name, handle, title, str(g), clock(t["duration"]), t["id"], slug)))
        print("%-18s %s" % (ag, " ".join(str(len(v)) for v in picked.values())), flush=True)
    # Genres interleaved, so any prefix of the batches seeds every station.
    rows = [r for rank in zip(*(v + [None] * (a.per - len(v)) for v in picked.values())) for r in rank if r]
    body = "".join("\t`%s`,\n" % "\n".join(rows[i:i + a.batch]) for i in range(0, len(rows), a.batch))
    with open(a.out, "w") as f:
        f.write("// Code generated by tools/curate/curate.py devseed from Audius trending lists. DO NOT EDIT.\n\n"
                "package devseed\n\nvar batches = []string{\n" + body + "}\n")
    print("%s: %d tracks in %d batches" % (a.out, len(rows), -(-len(rows) // a.batch)))
    for g, v in picked.items():
        print("%-24s %5d%s" % (GENRES[g], len(v), "  (short)" if len(v) < 150 else ""))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch")
    f.add_argument("--seeds", default=os.path.join(HERE, "seeds.json"))
    f.add_argument("--only", help="archive,ccmixter,audius")
    f.add_argument("--seed", help="fetch a single seed id (status ignored)")
    f.add_argument("--max-items", type=int, help="cap per seed (items for archive, tracks otherwise)")
    f.add_argument("--include-review", action="store_true", help="also fetch seeds with status to_review")
    sub.add_parser("loud", help="sampled loudness/clipping check (ffmpeg, first 60 s)")
    h = sub.add_parser("hash")
    h.add_argument("--max", type=int, default=20)
    b = sub.add_parser("batch")
    b.add_argument("--approved", default=os.path.join(HERE, "approved.json"))
    b.add_argument("--dry-run", action="store_true", help="check every row against the realm rules, write nothing")
    d = sub.add_parser("devseed")
    d.add_argument("--out", default=DEVSEED_OUT)
    d.add_argument("--per", type=int, default=250, help="tracks per genre")
    d.add_argument("--per-artist", type=int, default=6, help="tracks per artist")
    d.add_argument("--batch", type=int, default=85, help="tracks per devseed.Run call (gas)")
    a = p.parse_args()
    {"fetch": cmd_fetch, "hash": cmd_hash, "batch": cmd_batch, "loud": cmd_loud, "devseed": cmd_devseed}[a.cmd](a)


if __name__ == "__main__":
    main()
