#!/usr/bin/env python3
"""Build a batch of Audius and Jamendo pointers for tools/deploy/import.py.

    tools/curate/pointers.py audius <handle>... [--max N] [--out FILE]
    tools/curate/pointers.py jamendo <artist id>... [--max N] [--out FILE]   (JAMENDO_CLIENT_ID set)
    tools/curate/pointers.py --selftest

A pointer keeps only what the radio needs on chain: the platform id
(audius:<id>, jamendo:<id>), genre, duration and licence. No title, credits,
cover or link: both platforms' API terms allow session caching only, so the
app reads those live (app/netlify/refs.ts). Audius: streamable originals that
pass curate.py's own checks. Jamendo: CC0/BY/BY-SA/BY-NC/BY-NC-SA only (no ND).
The output is import.py's batch format, appended to --out if it exists.
"""
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import curate  # noqa: E402  (the same HTTP politeness, Audius checks and genre map)

JAMENDO = "https://api.jamendo.com/v3.0"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pointers_batch.json")
CC = re.compile(r"creativecommons\.org/(licenses/(by(?:-nc)?(?:-sa)?)/(\d\.\d)|publicdomain/zero/1\.0)")


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


def pointer(artist_key, audio, genre, sec, license_):
    return {"artist_key": artist_key, "title": "", "genre": genre, "duration": clock(sec), "license": license_, "credits": "",
            "audio": audio, "audio_sha256": "", "cover": "", "cover_sha256": "", "source_url": "", "attribution": ""}


def audius(handle, most):
    user = curate.http_json("%s/users/handle/%s?app_name=%s" % (curate.AUDIUS, urllib.parse.quote(handle), curate.APP))["data"]
    rows = curate.http_json("%s/users/%s/tracks?app_name=%s&limit=%d&sort=plays" % (curate.AUDIUS, user["id"], curate.APP, min(100, most * 3)))["data"]
    key = "audius-user:" + user["id"]
    tracks = [pointer(key, "audius:" + t["id"], curate.audius_genre(t.get("genre"), 1, t.get("tags") or ""), t["duration"], "")
              for t in rows if curate.audius_problem(t) is None][:most]
    return {"key": key, "kind": "audius", "name": "", "source_url": key}, tracks


def jamendo(artist_id, most):
    client = os.environ.get("JAMENDO_CLIENT_ID")
    if not client:
        sys.exit("set JAMENDO_CLIENT_ID")
    q = urllib.parse.urlencode({"client_id": client, "format": "json", "artist_id": artist_id, "limit": min(200, most * 3),
                                "include": "musicinfo licenses", "ccnd": "false", "order": "popularity_total"})
    rows = curate.http_json("%s/tracks/?%s" % (JAMENDO, q)).get("results", [])
    key = "jamendo-artist:" + str(artist_id)
    tracks = []
    for t in rows:
        lic, sec = cc_license(t.get("license_ccurl")), int(t.get("duration") or 0)
        if not lic or not t.get("audio") or not (curate.MIN_SEC <= sec <= curate.MAX_SEC):
            continue
        tags = " ".join((t.get("musicinfo") or {}).get("tags", {}).get("genres", []))
        tracks.append(pointer(key, "jamendo:" + str(t["id"]), curate.audius_genre(tags, 1, tags), sec, lic))
    return {"key": key, "kind": "jamendo", "name": "", "source_url": key}, tracks[:most]


def selftest():
    assert cc_license("http://creativecommons.org/licenses/by-nc-sa/3.0/") == "CC-BY-NC-SA-3.0"
    assert cc_license("https://creativecommons.org/licenses/by/4.0/") == "CC-BY-4.0"
    assert cc_license("http://creativecommons.org/publicdomain/zero/1.0/") == "CC0-1.0"
    assert cc_license("http://creativecommons.org/licenses/by-nc-nd/3.0/") is None
    assert clock(65) == "1:05"
    p = pointer("jamendo-artist:7", "jamendo:42", 3, 200, "CC-BY-4.0")
    assert p["title"] == "" and p["source_url"] == "" and p["duration"] == "3:20"
    print("ok")


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    most = int(argv[argv.index("--max") + 1]) if "--max" in argv else 60
    out = argv[argv.index("--out") + 1] if "--out" in argv else OUT
    args = [a for i, a in enumerate(argv) if not a.startswith("--") and (i == 0 or argv[i - 1] not in ("--max", "--out"))]
    if len(args) < 2 or args[0] not in ("audius", "jamendo"):
        sys.exit(__doc__)
    batch = json.load(open(out)) if os.path.exists(out) else {"artists": [], "tracks": []}
    have = {a["key"] for a in batch["artists"]} | {t["audio"] for t in batch["tracks"]}
    for ref in args[1:]:
        artist, tracks = (audius if args[0] == "audius" else jamendo)(ref, most)
        if artist["key"] not in have:
            batch["artists"].append(artist)
        new = [t for t in tracks if t["audio"] not in have]
        batch["tracks"] += new
        have |= {t["audio"] for t in new} | {artist["key"]}
        print("%s: %d pointers" % (artist["key"], len(new)))
    json.dump(batch, open(out, "w"), indent=1)
    print("wrote %s: %d artists, %d tracks" % (out, len(batch["artists"]), len(batch["tracks"])))


if __name__ == "__main__":
    main(sys.argv[1:])
