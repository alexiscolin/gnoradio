#!/usr/bin/env python3
"""Create the curated catalog's albums (tools/curate/albums_batch.json) with your gnokey key.

    tools/deploy/albums.py [--dry-run] [--password-once] [--first N] <onyx|mainnet> <gnokey key name> <namespace>

--first N creates only the next N albums (to check how they look before the rest).

As the catalog admin (who may edit an unclaimed artist): catalog.CreateAlbum for each
album whose tracks are not in an album yet. Tracks are found on chain by their audio
URL, artists by name, so a rerun skips what is done. Run it after import.py.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from importlib import import_module  # noqa: E402

imp = import_module("import")  # tools/deploy/import.py: qeval, gas price, gnokey call

GAS_BASE, GAS_TRACK = 45000000, 2000000  # measured on onyx: 37M for 6 tracks, 49M for 16 (about 30M + 1.2M a track), with margin
DEPOSIT = 3000000  # ugnot: the album record and the tracks' album field


def chain_tracks(remote, catalog):
    """audio -> (id, album) for every track on chain, read 100 at a time."""
    out, offset, total = {}, 0, None
    while total is None or offset < total:
        page = json.loads(json.loads(imp.qeval(remote, "%s.TracksJSON(%d, 100)" % (catalog, offset))[1:-len(" string)")]))
        total = page["total"]
        for t in page["tracks"]:
            out[t["audio"]] = (t["id"], t.get("album", 0))
        offset += 100
    return out


def main(argv):
    dry = "--dry-run" in argv
    once = "--password-once" in argv
    limit = int(argv[argv.index("--first") + 1]) if "--first" in argv else 0
    argv = [a for i, a in enumerate(argv) if not (i > 0 and argv[i - 1] == "--first")]
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 3 or args[0] not in imp.NETS:
        sys.exit(__doc__)
    net, key, ns = args[0], args[1], args[2].strip("/") + "/gnoradio"
    remote = imp.NETS[net][1]
    # The catalog release in force (v1, then v2 once a release took over), as the data realm names it.
    catalog = imp.qeval(remote, 'gno.land/r/%s/data.Writer("catalog")' % ns).split('"')[1]
    albums = json.load(open(os.path.join(os.path.dirname(__file__), "..", "curate", "albums_batch.json")))["albums"]
    print("reading the catalog's tracks on %s..." % net)
    tracks = chain_tracks(remote, catalog)
    todo = []
    for a in albums:
        ids = [tracks.get(u, (0, 0)) for u in a["audios"]]
        if any(i == 0 for i, _ in ids):
            print("skip (a track is not on chain): %s · %s" % (a["artist"], a["title"]))
        elif all(al == 0 for _, al in ids):
            todo.append((a, [i for i, _ in ids]))
    done = len(albums) - len(todo)
    todo = todo[:limit] if limit else todo
    price = imp.gas_price(remote)
    cost = sum(imp.fee(price, GAS_BASE + GAS_TRACK * len(ids)) for _, ids in todo)
    print("%d albums to create (%d done already), at most %.1f GNOT of fees + about %.1f GNOT of deposits" % (
        len(todo), done, cost / 1e6, len(todo) * 0.05))
    password = imp.getpass.getpass("gnokey password for %s: " % key) if once and not dry else None
    for n, (a, ids) in enumerate(todo, 1):
        aid = imp.first_int(imp.qeval(remote, "%s.ArtistByName(%s)" % (catalog, json.dumps(a["artist"]))))
        if aid == 0:
            print("skip (artist not on chain): %s" % a["artist"])
            continue
        gas = GAS_BASE + GAS_TRACK * len(ids)
        print("album %d/%d: %s · %s (%d tracks)" % (n, len(todo), a["artist"], a["title"], len(ids)))
        if not imp.call(net, key, catalog, "CreateAlbum", [aid, a["title"], a["cover"], a["cover_sha256"], a["year"], ",".join(map(str, ids))],
                        password, dry, imp.fee(price, gas), gas, DEPOSIT):
            sys.exit("CreateAlbum failed for %r: fix it and run again (done albums are skipped)" % a["title"])
    print("dry run: nothing was signed" if dry else "done")


if __name__ == "__main__":
    main(sys.argv[1:])
