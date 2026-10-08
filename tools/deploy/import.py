#!/usr/bin/env python3
"""Import the curated launch catalog (tools/curate/import_batch.json) with your gnokey key.

    tools/deploy/import.py [--dry-run] <onyx|mainnet> <gnokey key name> <namespace> [batch.json]

As the catalog admin: catalog.CreateArtist for each artist not on chain yet, then
radio.ImportTracks for the tracks, BATCH at a time (each joins its stations in the same
transaction; the realms load once per batch, which is most of a single import's gas).
It also imports Audius and Jamendo pointers (tools/curate/pointers.py builds that batch:
no title, the app reads it from the platform). It is resumable: artists are looked up by
name (catalog.ArtistByName), pointers by their platform id (ArtistByRef), imported
tracks are recorded next to the batch in import_done.<net>.<namespace>.json (one file per
network and namespace, "/" as "_"), so a rerun on the same chain skips them.
It prints the cost up front. gnokey asks for your password on each call unless you
pass --password-once (read once here, handed to gnokey on stdin, never stored).
"""
import base64
import getpass
import json
import os
import subprocess
import sys
import urllib.request

# Sign with the chains' gnokey release, the one tools/deploy/deploy.sh builds (an older
# gnokey on PATH may not match the chains); PATH's gnokey if it is not built yet.
GNOKEY = os.environ.get("GNOKEY") or (
    lambda p: p if os.access(p, os.X_OK) else "gnokey")(
    os.path.expanduser("~/.cache/gno-toolchains/onyx-v1.5.0/gnokey"))

NETS = {"onyx": ("onyx-1", "https://rpc.onyx.testnets.gno.land:443"),
        "mainnet": ("gnoland-1", "https://rpc.gno.land:443")}
# gno practice: simulate, then gas wanted = gas used x 1.5, fee = that gas at the live price + a
# small margin (the whole fee is charged, not the gas used). Measured by simulating
# radio.ImportTracks on the 5k-track devnet: 60.8M gas for one line, 735M for 25, so about
# 33M for the call and 28.1M per track.
BATCH = 25                     # radio.maxImportBatch
GAS_ONE = 91000000             # gas wanted for one call (CreateArtist): 1.5x a one-line import


def gas_for(n):
    """Gas wanted for an ImportTracks batch of n tracks: 1.5x the measured cost."""
    return int(1.5 * (33000000 + 28100000 * n))


PRICE_MARGIN = 1.2             # over the live gas price, against a rise before inclusion
DEPOSIT_ONE = 2000000          # ugnot of storage deposit allowed for one call
DEPOSIT_BATCH = 5000000        # for a batch (a track stores about 360 bytes: 0.036 GNOT); only what is stored is charged


def qeval(remote, expr):
    """The value of expr on chain, as gnokey's qeval prints it ("" on error)."""
    q = base64.b64encode(expr.encode()).decode()
    url = '%s/abci_query?path="vm/qeval"&data="%s"' % (remote, q)
    with urllib.request.urlopen(url.replace('"', "%22"), timeout=30) as r:
        res = json.load(r)["result"]["response"]["ResponseBase"]
    return "" if res.get("Error") else base64.b64decode(res.get("Data") or b"").decode()


def gas_price(remote):
    """The chain's live gas price (auth/gasprice), in ugnot per gas unit."""
    url = '%s/abci_query?path="auth/gasprice"' % remote
    with urllib.request.urlopen(url.replace('"', "%22"), timeout=30) as r:
        res = json.loads(r.read().decode(), strict=False)["result"]["response"]["ResponseBase"]
    p = json.loads(base64.b64decode(res["Data"]))
    return first_int(p["price"]) / int(p["gas"])


def fee(price, gas):
    """The fee in ugnot to offer for gas at price, plus PRICE_MARGIN."""
    return int(gas * price * PRICE_MARGIN) + 1


def first_int(s):
    digits = "".join(ch if ch.isdigit() else " " for ch in s).split()
    return int(digits[0]) if digits else 0


def call(net, key, pkg, func, args, password, dry, fee, gas, deposit):
    chain, remote = NETS[net]
    cmd = [GNOKEY, "maketx", "call", "-pkgpath", pkg, "-func", func]
    for a in args:
        cmd += ["-args", str(a)]
    cmd += ["-gas-fee", "%dugnot" % fee, "-gas-wanted", str(gas), "-max-deposit", "%dugnot" % deposit,
            "-chainid", chain, "-remote", remote, "-broadcast"]
    if password is not None:
        cmd += ["-insecure-password-stdin"]
    cmd += [key]
    if dry:
        print("  would run:", " ".join(cmd))
        return True
    r = subprocess.run(cmd, input=(password + "\n") if password is not None else None, text=True)
    return r.returncode == 0


def done_file(batch_path, net, ns):
    """The file of tracks already imported on this network and namespace, next to the batch."""
    return os.path.join(os.path.dirname(os.path.abspath(batch_path)), "import_done.%s.%s.json" % (net, ns.replace("/", "_")))


FIELDS = ("title", "genre", "duration", "license", "credits", "audio", "audio_sha256", "cover", "cover_sha256", "source_url", "attribution")


def batch_arg(tracks, ids):
    """radio.ImportTracks' argument: a line per track, ImportTrack's 12 arguments tab-separated."""
    lines = []
    for t in tracks:
        row = [str(ids[t["artist_key"]])] + [str(t[f]) for f in FIELDS]
        if any("\t" in v or "\n" in v for v in row):
            sys.exit("a tab or newline in %r: fix the batch file" % (t["title"] or t["audio"]))
        lines.append("\t".join(row))
    return "\n".join(lines)


def artist_lookup(catalog, a):
    """The expression that finds an artist already on chain: an Audius or Jamendo
    pointer by its platform id (it has no name), a curated artist by name."""
    if a["kind"] in ("audius", "jamendo"):
        return "%s.ArtistByRef(%s)" % (catalog, json.dumps(a["source_url"]))
    return "%s.ArtistByName(%s)" % (catalog, json.dumps(a["name"]))


def main(argv):
    dry = "--dry-run" in argv
    once = "--password-once" in argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) < 3 or args[0] not in NETS:
        sys.exit(__doc__)
    net, key, ns = args[0], args[1], args[2].strip("/") + "/gnoradio"
    batch_path = args[3] if len(args) > 3 else os.path.join(os.path.dirname(__file__), "..", "curate", "import_batch.json")
    done_path = done_file(batch_path, net, ns)
    batch = json.load(open(batch_path))
    done = json.load(open(done_path)) if os.path.exists(done_path) else {}
    remote = NETS[net][1]
    catalog, radio = "gno.land/r/%s/catalog/v1" % ns, "gno.land/r/%s/radio/v1" % ns

    todo = [t for t in batch["tracks"] if t["audio"] not in done]
    groups = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]
    print("%d artists, %d tracks to import (%d already done) in %d batches, on %s as %s" % (
        len(batch["artists"]), len(todo), len(batch["tracks"]) - len(todo), len(groups), net, ns))
    price = gas_price(remote)
    one, full = fee(price, GAS_ONE), fee(price, gas_for(BATCH))
    total = len(batch["artists"]) * one + sum(fee(price, gas_for(len(g))) for g in groups)
    print("cost: at most %.1f GNOT of fees (%d artists at %.3f, full batches at %.3f GNOT) + about %.0f GNOT of storage deposits" % (
        total / 1e6, len(batch["artists"]), one / 1e6, full / 1e6,
        len(todo) * 0.036 + len(batch["artists"]) * 0.05))
    password = getpass.getpass("gnokey password for %s: " % key) if once and not dry else None

    ids = {}
    for a in batch["artists"]:
        find = artist_lookup(catalog, a)
        aid = first_int(qeval(remote, find))
        if aid == 0:
            print("artist:", a["name"] or a["source_url"])
            if not call(net, key, catalog, "CreateArtist", [a["kind"], a["name"], "", a["source_url"]], password, dry, one, GAS_ONE, DEPOSIT_ONE):
                sys.exit("CreateArtist failed for %r: fix it and run again" % (a["name"] or a["source_url"]))
            aid = 0 if dry else first_int(qeval(remote, find))
        ids[a["key"]] = aid

    for i, g in enumerate(groups, 1):
        print("batch %d/%d: %s ... %s" % (i, len(groups), g[0]["title"] or g[0]["audio"], g[-1]["title"] or g[-1]["audio"]))
        if not call(net, key, radio, "ImportTracks", [batch_arg(g, ids)], password, dry, fee(price, gas_for(len(g))), gas_for(len(g)), DEPOSIT_BATCH):
            sys.exit("ImportTracks failed for batch %d: fix it and run again (done batches are skipped)" % i)
        if not dry:
            for t in g:
                done[t["audio"]] = True
            json.dump(done, open(done_path, "w"))
    print("dry run: nothing was signed" if dry else "done")


if __name__ == "__main__":
    main(sys.argv[1:])
