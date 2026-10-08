#!/usr/bin/env python3
"""Stage the GnoRadio packages for a public chain under another namespace.

On a local devnet the packages live at gno.land/{p,r}/gnoradio/...; on onyx they
go under the deployer's namespace: their gno.land name or their address,
e.g. nym-alexiscolin000/gnoradio (as gnogolf is under nym-alexiscolin000/gnogolf). This copies gno/ to
OUT with every "gno.land/{p,r}/gnoradio/" path rewritten (imports, gnomod.toml,
path constants), without tests and without the dev-only devseed realm.

    python3 tools/deploy/stage.py nym-alexiscolin000/gnoradio build/onyx [v2]

With a release (v2, v3...), the four rules realms are staged at that version
(their paths and every reference to them rewritten) and only they are printed:
the rest is staged too, for lint, but is already on chain. Then data.Propose
each of them (docs/DEPLOY.md, Upgrading the rules later).

Deploy order (each package imports only earlier ones): ORDER below. The data
realm has no version: it is never replaced (docs/ARCHITECTURE-v1.md). Deploy
release 1 right after data: data names <ns>/{catalog,radio,tickets,home}/v1 its
writers from the start, so nobody else may publish to those paths. The app
then builds with VITE_GNORADIO_NS set to the same namespace.
"""
import pathlib
import re
import shutil
import sys

ORDER = [
    "p/text/v0", "p/svg/v0", "p/store/v0", "p/safe/v0", "p/blocks/v0", "p/role/v0",
    "r/data",
    "r/catalog/v1", "r/tickets/nft", "r/tickets/v1", "r/radio/v1", "r/home/v1",
]


RULES = ["r/catalog/v1", "r/tickets/v1", "r/radio/v1", "r/home/v1"]


def stage(ns: str, out: pathlib.Path, release: str = "") -> list[pathlib.Path]:
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*(/[a-z0-9_]+)*", ns):
        sys.exit(f"bad namespace: {ns}")
    src = pathlib.Path(__file__).resolve().parents[2] / "gno"
    if release and not re.fullmatch(r"v([2-9]|[1-9][0-9])", release):
        sys.exit(f"bad release: {release} (v2, v3...)")
    if out.exists():
        shutil.rmtree(out)
    staged = []
    for pkg in ORDER:
        kind, rest = pkg.split("/", 1)
        to = rest[: -len("v1")] + release if release and pkg in RULES else rest
        dst = out / kind / ns / to
        dst.mkdir(parents=True)
        for f in sorted((src / kind / "gnoradio" / rest).iterdir()):
            if f.name.endswith("_test.gno") or f.suffix not in (".gno", ".toml"):
                continue
            text = f.read_text()
            if release:
                for r in RULES:
                    name = r.split("/")[1]
                    text = text.replace(f"gno.land/r/gnoradio/{name}/v1", f"gno.land/r/gnoradio/{name}/{release}")
            for k in ("p", "r"):
                text = text.replace(f"gno.land/{k}/gnoradio/", f"gno.land/{k}/{ns}/")
            (dst / f.name).write_text(text)
        if not release or pkg in RULES:
            staged.append(dst)
    return staged


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    for d in stage(sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3] if len(sys.argv) == 4 else ""):
        print(d)
