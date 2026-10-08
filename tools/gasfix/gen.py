#!/usr/bin/env python3
"""Writes the gas filetests of radio/v1 and catalog/v1 from one fixture per
realm (radio.tmpl, catalog.tmpl) and the mains in cases.txt.

A template is everything above main, with {{N}} (tracks), {{ARTISTS}} and
{{K}} (the size: 5k or 20k). A file keeps what follows main (// Output:,
// Gas:, // Storage:) byte for byte; a new one gets an empty // Gas: to
fill with `gno test -update-golden-tests`.

  python3 tools/gasfix/gen.py          write the files that differ
  python3 tools/gasfix/gen.py --check  fail if one differs or is not a case
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "gasfix"
DIRS = {"radio": "gno/r/gnoradio/radio/v1/filetests", "catalog": "gno/r/gnoradio/catalog/v1/filetests"}
SIZES = {"5k": (5000, 20), "20k": (20000, 80)}


def cases():
    case = None
    for line in (HERE / "cases.txt").read_text().splitlines():
        if line.startswith("\t") and case:
            case[3].append(line)
        elif line and not line.startswith("#"):
            if case:
                yield case
            realm, name, sizes = line.split("|")
            case = (realm, name, sizes.split(","), [])
    if case:
        yield case


def render(realm, size, body):
    n, artists = SIZES[size]
    head = (HERE / f"{realm}.tmpl").read_text()
    head = head.replace("{{N}}", str(n)).replace("{{ARTISTS}}", str(artists)).replace("{{K}}", size)
    return head + "func main(cur realm) {\n" + "\n".join(body) + "\n}\n"


def main():
    check = "--check" in sys.argv
    stale, made = [], set()
    for realm, name, sizes, body in cases():
        for size in sizes:
            path = ROOT / DIRS[realm] / f"z_gas_{name}_{size}_filetest.gno"
            made.add(path)
            old = path.read_text() if path.exists() else ""
            i = old.find("\n}\n", old.find("func main(cur realm) {"))
            new = render(realm, size, body) + (old[i + 3 :] if old else "\n// Gas:\n// 0\n")
            if new != old:
                stale.append(path)
                if not check:
                    path.write_text(new)
    for d in DIRS.values():
        for path in (ROOT / d).glob("z_gas_*_filetest.gno"):
            if re.search(r"_(5k|20k)_filetest\.gno$", path.name) and path not in made:
                stale.append(path)
                print("not a case:", path.relative_to(ROOT))
    for path in stale:
        print(("differs: " if check else "wrote: ") + str(path.relative_to(ROOT)))
    if check and stale:
        sys.exit(1)


main()
