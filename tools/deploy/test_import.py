#!/usr/bin/env python3
"""Self-check for import.py's parsing (no chain, no key): python3 tools/deploy/test_import.py"""
import io
import os
import sys
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util

spec = importlib.util.spec_from_file_location("imp", os.path.join(os.path.dirname(os.path.abspath(__file__)), "import.py"))
imp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(imp)

assert imp.first_int("(42 int)\n") == 42
assert imp.first_int("(0 int)") == 0
assert imp.first_int("") == 0
out = io.StringIO()
with redirect_stdout(out):
    assert imp.call("mainnet", "k", "gno.land/r/x/gnoradio/radio/v1", "ImportTrack", [3, "A b"], None, True, 112501, 75000000, 2000000)
line = out.getvalue()
assert "-chainid gnoland-1" in line and "-args 3 -args A b" in line and line.rstrip().endswith("-broadcast k"), line
# One done-file per network and namespace: a mainnet run must not skip what onyx already imported.
a = imp.done_file("/b/batch.json", "onyx", "alice/gnoradio")
assert os.path.basename(a) == "import_done.onyx.alice_gnoradio.json", a
assert a != imp.done_file("/b/batch.json", "mainnet", "alice/gnoradio")
assert a != imp.done_file("/b/batch.json", "onyx", "bob/gnoradio")
# A batch is a line per track, ImportTrack's 12 arguments tab-separated, in ImportTrack's order.
t = {"artist_key": "a", "title": "T", "genre": 3, "duration": "1:00", "license": "CC0-1.0", "credits": "",
     "audio": "ipfs://x", "audio_sha256": "", "cover": "", "cover_sha256": "", "source_url": "https://s", "attribution": "By"}
arg = imp.batch_arg([t, dict(t, title="U")], {"a": 7})
assert arg == "7\tT\t3\t1:00\tCC0-1.0\t\tipfs://x\t\t\t\thttps://s\tBy\n7\tU\t3\t1:00\tCC0-1.0\t\tipfs://x\t\t\t\thttps://s\tBy", arg
assert all(len(l.split("\t")) == 12 for l in arg.split("\n"))
assert imp.gas_for(25) == 1103250000 and imp.gas_for(25) < 3000000000  # under the block max
assert imp.fee(0.001, imp.gas_for(25)) == 1323901
print("ok")
