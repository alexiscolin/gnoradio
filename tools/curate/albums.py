#!/usr/bin/env python3
"""Group the curated catalog into albums: one per archive.org item and artist.

    python3 tools/curate/albums.py [import_batch.json] > tools/curate/albums_batch.json

Every curated track names the archive.org item it comes from (source_url). An item
with 3 tracks or more by one artist is a release: its title and year come from the
item's metadata, its cover from its first track (already hashed in the batch).
More than 40 tracks (catalog.maxAlbumTracks) splits into parts. tools/deploy/albums.py
then creates them on chain.
"""
import json
import os
import re
import sys
import unicodedata
import urllib.request

# archive.org items that are a catch-all rather than a release: no album.
SKIP_ITEMS = {"incompetech"}
MIN_TRACKS = 3
MAX_TRACKS = 40   # catalog maxAlbumTracks
MAX_TITLE = 64    # catalog maxTitle, in characters


def item_of(url):
    m = re.match(r"https://archive\.org/details/([^/?#]+)", url)
    return m.group(1) if m else ""


def metadata(item):
    with urllib.request.urlopen("https://archive.org/metadata/%s/metadata" % item, timeout=30) as r:
        return json.load(r).get("result", {})


def first(v):
    return (v[0] if isinstance(v, list) and v else v) or ""


def clean_title(raw, artist, item):
    t = re.sub(r"\s+", " ", first(raw)).strip()
    norm = lambda x: re.sub(r"^the|[^a-z0-9]", "", unicodedata.normalize("NFKD", x).encode("ascii", "ignore").decode().lower())
    same = lambda x: bool(norm(x)) and (norm(x) in norm(artist) or norm(artist) in norm(x) or norm(x) == "variousartists")
    t = re.sub(r"\s*\[[^\]]*\]\s*$", "", t)  # a netlabel's catalog number: "[treetrunk019]"
    t = re.sub(r"^\[[^\]]*\]\s*", "", t)
    if re.match(re.escape(artist) + r"\s+[-–—:]\s+", t, re.I):  # "Ambient Samurai - Ichiro NAKAGAWA - Title"
        t = t[len(artist):]
    t = t.strip(" -–—:")
    parts = [p.strip() for p in re.split(r"\s+[-–—]\s+", t) if p.strip()]
    if len(parts) > 1 and same(parts[0]):  # "Artist - Title", "Various Artists - Title"
        parts = parts[1:]
    if len(parts) > 1 and same(parts[-1]):  # "Title - Artist"
        parts = parts[:-1]
    t = " - ".join(parts) or item.replace("_", " ").replace("-", " ")
    q = re.search(r'["“«]([^"”»]+)["”»]', t)  # FloatingMind "Human Kalor": the quoted title
    if q and same(t.replace(q.group(0), "")):
        t = q.group(1)
    return valid(t)


def valid(t):
    """The title as catalog's text.Valid accepts it: letters, digits, spaces and . , ' - ! ? : / & only."""
    t = re.sub(r"\s*[(\[][A-Z]{2,}[A-Z0-9-]*\d[)\]]", "", t)  # a catalog number: "(TDC043)"
    t = re.sub(r"\s*[(\[]([^)\]]*)[)\]]", r" - \1", t)  # "Cipher (Sampler)" -> "Cipher - Sampler"
    t = t.replace("…", "...").replace("’", "'").replace("‘", "'")
    t = "".join(c if c.isalpha() or c.isdigit() or c in " .,'-!?:/&" else " " for c in t)
    t = re.sub(r"\s+", " ", t).strip(" -")
    return t if len(t) <= MAX_TITLE else t[: MAX_TITLE - 3].rstrip(" -") + "..."


def year_of(md):
    for k in ("year", "date", "publicdate", "addeddate"):
        m = re.search(r"(19|20)\d\d", first(md.get(k, "")))
        if m:
            return int(m.group(0))
    return 2000


def main(path):
    batch = json.load(open(path))
    names = {a["key"]: a["name"] for a in batch["artists"]}
    groups = {}
    for t in batch["tracks"]:
        groups.setdefault((item_of(t["source_url"]), t["artist_key"]), []).append(t)
    # One release may sit in several archive.org items (an album and its bonus tracks uploaded apart):
    # items of one artist with the same title make one album.
    releases = {}
    for (item, key), tracks in sorted(groups.items()):
        if not item or any(k in item.lower() for k in SKIP_ITEMS):
            continue
        md = metadata(item)
        title = clean_title(md.get("title", ""), names[key], item)
        r = releases.setdefault((key, title.lower()), {"title": title, "md": md, "item": item, "tracks": [], "size": 0})
        if len(tracks) > r["size"]:  # the biggest item gives the year and the cover
            r.update(md=md, item=item, size=len(tracks))
        r["tracks"] += tracks
    albums = []
    for (key, _), r in sorted(releases.items(), key=lambda kv: (kv[1]["item"], kv[0][0])):
        tracks, title, md, item = r["tracks"], r["title"], r["md"], r["item"]
        if len(tracks) < MIN_TRACKS:
            continue
        cover = next((t for t in tracks if t["cover"] and t["cover_sha256"]), {"cover": "", "cover_sha256": ""})
        parts = [tracks[i:i + MAX_TRACKS] for i in range(0, len(tracks), MAX_TRACKS)]
        for n, part in enumerate(parts, 1):
            name = title if len(parts) == 1 else valid("%s - part %d" % (title[: MAX_TITLE - 9], n))
            albums.append({"artist_key": key, "artist": names[key], "item": item, "title": name, "year": year_of(md),
                           "cover": cover["cover"], "cover_sha256": cover["cover_sha256"], "audios": [t["audio"] for t in part]})
        print("%-40s %-28s %3d tracks  %s" % (item[:40], names[key][:28], len(tracks), title), file=sys.stderr)
    json.dump({"albums": albums}, sys.stdout, indent=1, ensure_ascii=False)
    print("\n%d albums, %d tracks" % (len(albums), sum(len(a["audios"]) for a in albums)), file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "import_batch.json"))
