#!/usr/bin/env python3
"""Stage the GnoRadio packages for a public chain under another namespace.

On a local devnet the packages live at gno.land/{p,r}/gnoradio/...; on onyx they
go under the deployer's namespace: their gno.land name or their address,
e.g. nym-alexiscolin000/gnoradio (as gnogolf is under nym-alexiscolin000/gnogolf). This copies gno/ to
OUT with every "gno.land/{p,r}/gnoradio/" path rewritten (imports, gnomod.toml,
path constants), without tests and without the dev-only devseed realm.

    python3 tools/deploy/stage.py nym-alexiscolin000/gnoradio build/onyx

Deploy order (each package imports only earlier ones): p/text, p/svg, p/store,
p/safe, p/blocks, r/catalog, r/radio, r/tickets, r/home. The app then builds
with VITE_GNORADIO_NS set to the same namespace.
"""
import pathlib
import re
import shutil
import sys

ORDER = ["p/text", "p/svg", "p/store", "p/safe", "p/blocks", "r/catalog", "r/radio", "r/tickets", "r/home"]


def stage(ns: str, out: pathlib.Path) -> list[pathlib.Path]:
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*(/[a-z0-9_]+)*", ns):
        sys.exit(f"bad namespace: {ns}")
    src = pathlib.Path(__file__).resolve().parents[2] / "gno"
    if out.exists():
        shutil.rmtree(out)
    staged = []
    for pkg in ORDER:
        kind, name = pkg.split("/")
        dst = out / kind / ns / name / "v0"
        dst.mkdir(parents=True)
        for f in sorted((src / kind / "gnoradio" / name / "v0").iterdir()):
            if f.name.endswith("_test.gno") or f.suffix not in (".gno", ".toml"):
                continue
            text = f.read_text()
            for k in ("p", "r"):
                text = text.replace(f"gno.land/{k}/gnoradio/", f"gno.land/{k}/{ns}/")
            (dst / f.name).write_text(text)
        staged.append(dst)
    return staged


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    for d in stage(sys.argv[1], pathlib.Path(sys.argv[2])):
        print(d)
