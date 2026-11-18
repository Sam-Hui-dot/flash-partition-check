"""Count maintained non-test MoonBit source, separately from CLI lines."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
total = core = 0
for file in sorted(root.rglob("*.mbt")):
    relative = file.relative_to(root)
    if any(item in {"_build", ".git", ".mooncakes", "vendor"} for item in relative.parts):
        continue
    if file.name.endswith(("_test.mbt", "_wbtest.mbt")):
        continue
    content = file.read_text(encoding="utf-8").splitlines()
    code = [line.strip() for line in content if line.strip()]
    if any(line.startswith("/*") for line in code):
        raise SystemExit(f"unexpected block comment in {relative}")
    size = sum(not line.startswith(("//", "#|", 'extern "js"')) for line in code)
    print(f"{relative.as_posix()}: {size}")
    total += size
    if relative.parts[0] != "cmd":
        core += size
print(f"Core: {core}; total: {total}")
