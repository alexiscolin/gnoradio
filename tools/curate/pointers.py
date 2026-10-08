#!/usr/bin/env python3
"""Build a batch of Audius and Jamendo pointers for tools/deploy/import.py.

    tools/curate/pointers.py audius <handle>... [--max N] [--out FILE]
    tools/curate/pointers.py jamendo <artist id>... [--max N] [--out FILE]   (JAMENDO_CLIENT_ID set)
    tools/curate/pointers.py --selftest

A pointer keeps only what the radio needs on chain: the platform id
(audius:<id>, jamendo:<id>), genre, duration and licence. No title, credits,
cover or link: both platforms' API terms allow session caching only, so the
app reads those live (app/netlify/refs.ts). Audius: streamable originals that
pass curate.py's own checks. Jamendo: CC0/BY/BY-SA/BY-NC/BY-NC-SA, unported 1.0-4.0 (no ND).
The output is import.py's batch format, appended to --out if it exists.
"""
import json
import os
import re
import sys
import urllib.parse

JAMENDO_CALLS = 0
SEEDS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pointer_seeds.json")
# titles that betray a loop, sketch or library cue rather than a song
SKETCH = re.compile(r"\b(loop|sketch|demo|jingle|intro|outro|stinger|logo|bumper|ident|preview|snippet|bgm|corporate|commercial|background|trailer|promo|instrumental)\b", re.I)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import curate  # noqa: E402  (the same HTTP politeness, Audius checks and genre map)

JAMENDO = "https://api.jamendo.com/v3.0"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pointers_batch.json")
CC = re.compile(r"creativecommons\.org/(licenses/(by(?:-nc)?(?:-sa)?)/((?:1|2|4)\.0|2\.5|3\.0)/?(?:$|[?#])|publicdomain/zero/1\.0)")


def clock(sec):
    return "%d:%02d" % (int(sec) // 60, int(sec) % 60)


def cc_license(url):
    """SPDX id of a Creative Commons deed URL we accept (no ND), else None."""
    m = CC.search(url or "")
    if not m:
        return None
    if m.group(1).startswith("publicdomain"):
        return "CC0-1.0"
    return "CC-%s-%s" % (m.group(2).upper(), m.group(3))


def pointer(artist_key, audio, genre, sec, license_, pop=0):
    return {"pop": pop, "artist_key": artist_key, "title": "", "genre": genre, "duration": clock(sec), "license": license_, "credits": "",
            "audio": audio, "audio_sha256": "", "cover": "", "cover_sha256": "", "source_url": "", "attribution": ""}


def span(genre):
    return curate.LONG_MAX_SEC if genre in curate.LONG_GENRES else curate.MAX_SEC


def audius(handle, most, genre=None):
    user = curate.http_json("%s/users/handle/%s?app_name=%s" % (curate.AUDIUS, urllib.parse.quote(handle), curate.APP))["data"]
    rows = curate.http_json("%s/users/%s/tracks?app_name=%s&limit=%d&sort=plays" % (curate.AUDIUS, user["id"], curate.APP, min(100, most * 3)))["data"]
    key = "audius-user:" + user["id"]
    tracks = [pointer(key, "audius:" + t["id"], genre or curate.audius_genre(t.get("genre"), 1, t.get("tags") or ""), t["duration"], "", t.get("play_count") or 0)
              for t in rows if curate.audius_problem(t, span(genre)) is None
              and not SKETCH.search(t.get("title", ""))][:most]
    return {"key": key, "kind": "audius", "name": "", "source_url": key}, tracks


def jamendo_get(client, **kw):
    global JAMENDO_CALLS
    JAMENDO_CALLS += 1
    q = urllib.parse.urlencode(dict({"client_id": client, "format": "json", "include": "musicinfo stats", "ccnd": "false"}, **kw))
    return curate.http_json("%s/tracks/?%s" % (JAMENDO, q), host_delay=0.3).get("results", [])


def jamendo(artist_id, most, genre=None, ids=None):
    client = os.environ.get("JAMENDO_CLIENT_ID")
    if not client:
        sys.exit("set JAMENDO_CLIENT_ID")
    if ids:
        rows = jamendo_get(client, id=" ".join(map(str, ids)), limit=50)
    else:
        rows = jamendo_get(client, artist_id=artist_id, limit=min(200, most * 3), order="popularity_total")
        if not rows:  # Jamendo drops tracks without play stats when ordering by popularity
            rows = jamendo_get(client, artist_id=artist_id, limit=min(200, most * 3))
    key = "jamendo-artist:" + str(artist_id)
    tracks = []
    for t in rows:
        if str(t.get("artist_id")) != str(artist_id):
            continue
        lic, sec = cc_license(t.get("license_ccurl")), int(t.get("duration") or 0)
        if not lic or not t.get("audio") or not (curate.MIN_SEC <= sec <= span(genre)) or (SKETCH.search(t.get("name", "")) and not ids):
            continue
        tg = " ".join((t.get("musicinfo") or {}).get("tags", {}).get("genres", []))
        tracks.append(pointer(key, "jamendo:" + str(t["id"]), genre or curate.audius_genre(tg, 1, tg), sec, lic,
                             int((t.get("stats") or {}).get("rate_listened_total") or 0)))
    return {"key": key, "kind": "jamendo", "name": "", "source_url": key}, tracks[:most]


def add(batch, have, artist, tracks):
    """Append the artist (only when it has tracks) and its tracks not seen yet; returns the new tracks."""
    new = [t for t in tracks if t["audio"] not in have]
    if new and artist["key"] not in have:
        batch["artists"].append(artist)
    batch["tracks"] += new
    have |= {t["audio"] for t in new} | ({artist["key"]} if new else set())
    return new


def build(path, out):
    """Rebuild the whole batch from the pointer seed file (Jamendo, then Audius)."""
    seeds = json.load(open(path))
    batch = {"artists": [], "tracks": []}
    have = set()
    for kind, rows in (("jamendo", seeds.get("jamendo", [])), ("audius", seeds.get("audius", []))):
        for sd in rows:
            if sd.get("status", "approved") != "approved":
                continue
            if kind == "audius":
                artist, tracks = audius(sd["handle"], sd["max"], sd["genre"])
            else:
                artist, tracks = jamendo(sd["artist"], sd["max"], sd["genre"], sd.get("ids"))
            new = add(batch, have, artist, tracks)
            print("%s %s: %d pointers" % (kind, sd.get("name") or sd.get("handle") or sd.get("artist"), len(new)), flush=True)
    json.dump(batch, open(out, "w"), indent=1)
    print("wrote %s: %d artists, %d tracks; jamendo calls %d" % (out, len(batch["artists"]), len(batch["tracks"]), JAMENDO_CALLS))


def selftest():
    assert cc_license("http://creativecommons.org/licenses/by-nc-sa/3.0/") == "CC-BY-NC-SA-3.0"
    assert cc_license("https://creativecommons.org/licenses/by/4.0/") == "CC-BY-4.0"
    assert cc_license("http://creativecommons.org/publicdomain/zero/1.0/") == "CC0-1.0"
    assert cc_license("http://creativecommons.org/licenses/by-nc-nd/3.0/") is None
    assert cc_license("http://creativecommons.org/licenses/by-sa/2.5/") == "CC-BY-SA-2.5"
    assert cc_license("https://creativecommons.org/licenses/by/1.0") == "CC-BY-1.0"
    assert cc_license("http://creativecommons.org/licenses/by-sa/2.5/es/") is None
    assert cc_license("http://creativecommons.org/licenses/by-nd/2.5/") is None
    assert cc_license("http://creativecommons.org/publicdomain/mark/1.0/") is None
    assert SKETCH.search("Drum Loop 4") and not SKETCH.search("Lovely")
    assert clock(65) == "1:05"
    p = pointer("jamendo-artist:7", "jamendo:42", 3, 200, "CC-BY-4.0")
    assert p["title"] == "" and p["source_url"] == "" and p["duration"] == "3:20"
    print("ok")


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    if argv[:1] == ["seeds"]:
        rest = [a for i, a in enumerate(argv[1:]) if not a.startswith("--") and (i == 0 or argv[i] != "--out")]
        return build(rest[0] if rest else SEEDS, argv[argv.index("--out") + 1] if "--out" in argv else OUT)
    most = int(argv[argv.index("--max") + 1]) if "--max" in argv else 60
    out = argv[argv.index("--out") + 1] if "--out" in argv else OUT
    args = [a for i, a in enumerate(argv) if not a.startswith("--") and (i == 0 or argv[i - 1] not in ("--max", "--out"))]
    if len(args) < 2 or args[0] not in ("audius", "jamendo"):
        sys.exit(__doc__)
    batch = json.load(open(out)) if os.path.exists(out) else {"artists": [], "tracks": []}
    have = {a["key"] for a in batch["artists"]} | {t["audio"] for t in batch["tracks"]}
    for ref in args[1:]:
        artist, tracks = (audius if args[0] == "audius" else jamendo)(ref, most)
        new = add(batch, have, artist, tracks)
        print("%s: %d pointers" % (artist["key"], len(new)))
    json.dump(batch, open(out, "w"), indent=1)
    print("wrote %s: %d artists, %d tracks" % (out, len(batch["artists"]), len(batch["tracks"])))


if __name__ == "__main__":
    main(sys.argv[1:])
