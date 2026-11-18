"""Compare multi-image reports against address sets decoded by IntelHex."""
import json
import subprocess
import tempfile
from pathlib import Path

from intelhex import IntelHex

root = Path(__file__).resolve().parent
cli = root.parent / "_build/js/debug/build/cmd/main/main.js"
cache = root / "_build/makerdiary"
source = cache / "ble_app_blinky_nrf52840_mdk_s140.hex"


def check(folder, images, partitions):
    plan = {
        "partitions": partitions,
        "images": [
            {"name": name, "file": path.name, "partition": partition}
            for name, path, partition in images
        ],
    }
    manifest = folder / "plan.json"
    manifest.write_text(json.dumps(plan), encoding="utf-8")
    result = subprocess.run(
        ["node", str(cli), "--manifest", str(manifest), "--json"],
        capture_output=True, text=True, encoding="utf-8",
    )
    assert result.stdout, result.stderr
    report = json.loads(result.stdout)
    decoded = {name: set(IntelHex(str(path)).addresses()) for name, path, _ in images}
    by_name = {p["name"]: (int(p["start"], 16), int(p["start"], 16) + int(p["size"], 16))
               for p in partitions}
    expected = {}
    for index, (name, _, partition) in enumerate(images):
        lo, hi = by_name[partition]
        expected["outside_partition", name, partition] = {
            address for address in decoded[name] if not lo <= address < hi
        }
        for item in partitions:
            if item.get("reserved"):
                lo, hi = by_name[item["name"]]
                expected["reserved_write", name, item["name"]] = {
                    address for address in decoded[name] if lo <= address < hi
                }
        for earlier, _, _ in images[:index]:
            expected["collision", earlier, name] = decoded[earlier] & decoded[name]
    actual = {}
    for issue in report["issues"]:
        key = issue["kind"], issue["image"], issue["target"]
        assert issue["line"] >= 1, issue
        if issue["kind"] == "collision":
            assert issue["other_line"] >= 1, issue
        actual.setdefault(key, set()).update(
            range(int(issue["first"], 16), int(issue["end_exclusive"], 16))
        )
    expected = {k: v for k, v in expected.items() if v}
    assert actual == expected, ([(k, len(v)) for k, v in actual.items()],
                                [(k, len(v)) for k, v in expected.items()])
    assert result.returncode == (1 if expected else 0), result
    assert report["issue_count"] == len(report["issues"]), report
    assert {x["name"]: int(x["bytes"]) for x in report["images"]} == {
        name: len(values) for name, values in decoded.items()
    }, report
    return {k[0]: sum(len(v) for key, v in expected.items() if key[0] == k[0])
            for k in expected}


parts = [
    {"name": "system", "start": "0x0", "size": "0x26000"},
    {"name": "application", "start": "0x26000", "size": "0xc7000"},
    {"name": "configuration", "start": "0xed000", "size": "0x13000", "reserved": True},
]
with tempfile.TemporaryDirectory() as directory:
    folder = Path(directory)
    firmware = IntelHex(str(source))
    stack, application = (folder / name for name in ("system.hex", "application.hex"))
    for image, path in [(firmware[0:0x26000], stack), (firmware[0x26000:0xed000], application)]:
        image.start_addr = None
        image.write_hex_file(str(path))
    assert not check(folder, [("system", stack, "system"), ("app", application, "application")], parts)
    wrong = folder / "full-with-reserved-byte.hex"
    firmware[0xed00a] = 0xA5  # Deliberate fixture mutation, not from the vendor.
    firmware.write_hex_file(str(wrong))
    issues = check(folder, [("system", stack, "system"), ("app", wrong, "application")], parts)
    assert issues["reserved_write"] == 1 and issues["collision"] == len(IntelHex(str(stack))), issues
    print(json.dumps({"clean_vendor_partition_plan": "pass", "mutated_full_image": issues},
                     indent=2))
