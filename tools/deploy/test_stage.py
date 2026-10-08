"""stage.py: every gnoradio path is rewritten, and each package imports only earlier ones.

    python3 tools/deploy/test_stage.py
"""
import pathlib
import re
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from stage import stage  # noqa: E402

NS = "nym-test000/gnoradio"
with tempfile.TemporaryDirectory() as tmp:
    out = pathlib.Path(tmp)
    dirs = stage(NS, out)
    seen = set()
    for d in dirs:
        rel = d.relative_to(out)
        path = f"gno.land/{rel}"
        files = sorted(d.iterdir())
        assert files and not any(f.name.endswith("_test.gno") for f in files), path
        text = "\n".join(f.read_text() for f in files)
        assert not re.search(r"gno\.land/[pr]/gnoradio/", text), f"{path} keeps a devnet path"
        assert f'module = "{path}"' in text, f"{path}: gnomod.toml not rewritten"
        for dep in set(re.findall(rf'"(gno\.land/[pr]/{NS}/[^"]+)"', text)) - {path}:
            assert dep in seen, f"{path} imports {dep} before it is deployed"
        seen.add(path)
    assert len(dirs) == 12, len(dirs)
print("stage.py ok")
