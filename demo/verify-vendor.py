import hashlib
import json
import subprocess
import urllib.request
from pathlib import Path
from intelhex import IntelHex

root = Path(__file__).resolve().parent
cache = root / "_build" / "makerdiary"
cache.mkdir(parents=True, exist_ok=True)
revision = "52ba5cb08562324e58a3090ff6a17c7b2daa7d2e"
prefix = f"https://raw.githubusercontent.com/makerdiary/nrf52840-mdk/{revision}/examples/nrf5-sdk"
cli = root.parent / "_build/js/debug/build/cmd/main/main.js"
receipts = []
for name in ("ble_app_blinky", "ble_app_hrs"):
    script_name = f"{name}_gcc_nrf52.ld"
    firmware_name = f"{name}_nrf52840_mdk_s140.hex"
    downloaded = []
    for filename, path in (
        (script_name, f"{name}/armgcc/{script_name}"),
        (firmware_name, f"{name}/hex/{firmware_name}"),
    ):
        url = f"{prefix}/{path}"
        data = urllib.request.urlopen(url, timeout=30).read()
        local = cache / filename
        local.write_bytes(data)
        downloaded.append({"url": url, "sha256": hashlib.sha256(data).hexdigest()})
    combined = IntelHex(str(cache / firmware_name))
    first, end = 0x26000, 0x100000
    application = combined[first:end]
    application.start_addr = None
    application_path = cache / (name + "_application.hex")
    application.write_hex_file(str(application_path))
    expected_violations = []
    for start, stop in combined.segments():
        if start < first:
            expected_violations.append((start, min(stop, first)))
        if stop > end:
            expected_violations.append((max(start, end), stop))
    assert application.segments()
    for image, expected_code in ((application_path, 0), (cache / firmware_name, 1)):
        run = subprocess.run(
            ["node", str(cli), "--linker", str(image), str(cache / script_name), "FLASH"],
            capture_output=True, text=True,
        )
        assert run.returncode == expected_code, run.stdout + run.stderr
        if expected_code == 1:
            assert f"FAIL: {len(expected_violations)} " in run.stdout
            for start, stop in expected_violations:
                assert f"[0x{start:x}, 0x{stop:x})" in run.stdout
        receipts.append({"example": name, "image": image.name, "exit_code": run.returncode,
                         "application_bytes": len(application),
                         "application_segments": application.segments(),
                         "oracle_violations": expected_violations,
                         "sources": downloaded, "output": run.stdout.strip()})
print(json.dumps(receipts, ensure_ascii=False, indent=2))

